import Foundation
import SwiftUI

struct HexEdit: Identifiable, Hashable {
    let id = UUID()
    let offset: Int
    let originalValue: UInt8
    let newValue: UInt8
}

struct Page {
    let index: Int
    let startOffset: Int
    let bytes: [UInt8]
}

enum SearchType {
    case hex
    case ascii
}

@MainActor
class HexEditorViewModel: ObservableObject {
    // MARK: - Published Properties for UI
    @Published var edits: [Int: HexEdit] = [:]
    @Published var selectedOffset: Int? = nil
    @Published var highlightedOffset: Int? = nil
    @Published var bytesPerRow: Int = 8
    @Published private(set) var pageCache: [Int: Page] = [:]
    @Published var searchText: String = ""
    @Published var scrollToID: Int? = nil
    
    // MARK: - File & Paging Properties
    let fileURL: URL
    let fileSize: Int
    private let fileHandle: FileHandle
    
    let pageSize: Int = 65536
    let totalPages: Int
    
    private let pageCacheLimit = 5
    private var pageAccessHistory: [Int] = []
    private let fileQueue = DispatchQueue(label: "com.speedy67.hexeditor.fileio", qos: .userInitiated)
    
    // MARK: - Initialization
    
    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.fileHandle = try FileHandle(forReadingFrom: fileURL)
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        self.fileSize = Int(size)
        self.totalPages = (self.fileSize + pageSize - 1) / pageSize

        loadPage(0)
    }
    
    deinit {
        try? fileHandle.close()
        print("HexEditorViewModel deinitialized.")
    }
    
    // MARK: - Public API for SwiftUI Views
    
    var totalRowCount: Int { (fileSize + bytesPerRow - 1) / bytesPerRow }
    
    func byte(at offset: Int) -> UInt8? {
        guard offset < fileSize else { return nil }
        let pageIndex = offset / pageSize
        
        if let page = pageCache[pageIndex] {
            let localOffset = offset - page.startOffset
            guard localOffset < page.bytes.count else { return nil }
            return edits[offset]?.newValue ?? page.bytes[localOffset]
        }
        return nil
    }
    
    func rowDidAppear(rowIndex: Int) {
        let requiredOffset = rowIndex * bytesPerRow
        guard requiredOffset < fileSize else { return }
        let requiredPageIndex = requiredOffset / pageSize
        let pagesToLoad = Set((requiredPageIndex-1)...(requiredPageIndex+1))
        
        for pageIndex in pagesToLoad {
            if pageIndex >= 0 && pageIndex < totalPages && pageCache[pageIndex] == nil {
                loadPage(pageIndex)
            }
        }
    }
    
    // MARK: - Page Loading & Eviction Logic
    
    private func loadPage(_ pageIndex: Int) {
        guard pageCache[pageIndex] == nil else {
            updateAccessHistory(for: pageIndex)
            return
        }
        
        if pageCache.count >= pageCacheLimit {
            evictOldestPage()
        }
        
        print("HexEditor: Submitting load task for page \(pageIndex)...")
        
        fileQueue.async {
            let start = pageIndex * self.pageSize
            let length = min(self.pageSize, self.fileSize - start)
            
            guard length > 0 else { return }
            
            var pageData: [UInt8]? = nil
            do {
                try self.fileHandle.seek(toOffset: UInt64(start))
                let data = self.fileHandle.readData(ofLength: length)
                pageData = [UInt8](data)
            } catch {
                print("HexEditor Error: FileHandle seek/read failed for page \(pageIndex): \(error)")
            }
            
            if let bytes = pageData {
                DispatchQueue.main.async {
                    let newPage = Page(index: pageIndex, startOffset: start, bytes: bytes)
                    self.pageCache[pageIndex] = newPage
                    self.updateAccessHistory(for: pageIndex)
                    print("HexEditor: Page \(pageIndex) loaded. Cache size: \(self.pageCache.count)")
                }
            }
        }
    }
    
    private func evictOldestPage() {
        if let pageToEvict = pageAccessHistory.first {
            print("HexEditor: Cache limit reached. Evicting page \(pageToEvict).")
            pageCache.removeValue(forKey: pageToEvict)
            pageAccessHistory.removeFirst()
        }
    }
    
    private func updateAccessHistory(for pageIndex: Int) {
        pageAccessHistory.removeAll { $0 == pageIndex }
        pageAccessHistory.append(pageIndex)
    }
    
    // MARK: - Edit & Search Logic (Largely unchanged but adapted for pages)
    
    func applyEdit(offset: Int, newValue: UInt8) {
        let originalValue = edits[offset]?.originalValue ?? getOriginalByte(at: offset)
        
        if newValue == originalValue {
            if edits.removeValue(forKey: offset) != nil {
                objectWillChange.send()
            }
            return
        }
        
        let edit = HexEdit(offset: offset, originalValue: originalValue, newValue: newValue)
        edits[offset] = edit
        
        objectWillChange.send()
    }

    /// Synchronously reads the original byte value from the file at a specific offset.
    /// Note: This performs blocking I/O and should be used sparingly.
    private func getOriginalByte(at offset: Int) -> UInt8 {
        let pageIndex = offset / pageSize
        if let page = pageCache[pageIndex] {
            let localOffset = offset - page.startOffset
            if localOffset < page.bytes.count {
                return page.bytes[localOffset]
            }
        }
        do {
            try fileHandle.seek(toOffset: UInt64(offset))
            let data = fileHandle.readData(ofLength: 1)
            return data.first ?? 0x00
        } catch {
            print("Error reading original byte at offset \(offset): \(error)")
            return 0x00
        }
    }
    
    func isOffsetModified(_ offset: Int) -> Bool {
        return edits[offset] != nil
    }
    
    func revertAllEdits() {
        edits.removeAll()
        objectWillChange.send()
    }
    
    /// Generates the fully patched data blob by reading the original file and applying edits.
    /// This is an async throwing function to be called from a Task.
    func generatePatchedData() async throws -> Data {
        print("HexEditor: Generating patched data...")
        var data: Data
        data = try await fileHandle.readToEnd() ?? Data()
        
        for (_, edit) in edits {
            guard edit.offset < data.count else { continue }
            data[edit.offset] = edit.newValue
        }
        print("HexEditor: Finished generating patched data.")
        return data
    }
    
    // MARK: - Search Logic

    func search(searchText: String, searchType: SearchType) {
        guard !searchText.isEmpty else { return }

        fileQueue.async { [weak self] in
            guard let self = self else { return }

            let searchData: Data
            switch searchType {
            case .hex:
                var hexBytes = [UInt8]()
                var hexString = searchText.replacingOccurrences(of: " ", with: "")
                if hexString.count % 2 != 0 {
                    hexString += "0"
                }
                var index = hexString.startIndex
                while index < hexString.endIndex {
                    let nextIndex = hexString.index(index, offsetBy: 2)
                    if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                        hexBytes.append(byte)
                    } else {
                        print("HexEditor Error: Invalid hex string character.")
                        return
                    }
                    index = nextIndex
                }
                searchData = Data(hexBytes)
            case .ascii:
                searchData = searchText.data(using: .ascii) ?? Data()
            }

            guard !searchData.isEmpty else { return }

            let startOffset = (self.selectedOffset ?? -1) + 1

            for offset in startOffset..<self.fileSize {
                guard offset + searchData.count <= self.fileSize else { break }

                var match = true
                for i in 0..<searchData.count {
                    guard let byte = self.byte(at: offset + i) else {
                        match = false
                        break
                    }
                    if byte != searchData[i] {
                        match = false
                        break
                    }
                }

                if match {
                    DispatchQueue.main.async {
                        self.selectedOffset = offset
                        self.scrollToID = offset / self.bytesPerRow
                    }
                    return
                }
            }

            if startOffset > 0 {
                for offset in 0..<startOffset {
                    guard offset + searchData.count <= self.fileSize else { break }

                    var match = true
                    for i in 0..<searchData.count {
                        guard let byte = self.byte(at: offset + i) else {
                            match = false
                            break
                        }
                        if byte != searchData[i] {
                            match = false
                            break
                        }
                    }

                    if match {
                        DispatchQueue.main.async {
                            self.selectedOffset = offset
                            self.scrollToID = offset / self.bytesPerRow
                        }
                        return
                    }
                }
            }
            DispatchQueue.main.async {
                self.selectedOffset = nil
            }
        }
    }
}
