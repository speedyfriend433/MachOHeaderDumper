import Foundation

struct HexEdit: Identifiable, Hashable {
    let id = UUID()
    let offset: Int
    let originalValue: UInt8
    let newValue: UInt8
}

@MainActor
class HexEditorViewModel: ObservableObject {
    @Published var data: Data
    @Published var edits: [Int: HexEdit] = [:]
    @Published var selectedOffset: Int? = nil
    @Published var foundOffsets: [Int] = []
    @Published var highlightedOffset: Int? = nil

    let fileURL: URL
    private var fileHandle: FileHandle?
    private var fileSize: Int
    @Published var bytesPerRow: Int = 8
    let pageSize: Int = 4096 
    @Published private(set) var currentPage: Int = 0
    private var totalPages: Int

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.fileHandle = try FileHandle(forReadingFrom: fileURL)
        self.fileSize = Int(try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        self.totalPages = (self.fileSize + pageSize - 1) / pageSize
        self.data = Data()
        loadPage(0)
    }

    deinit {
        try? fileHandle?.close()
    }

    func loadPage(_ page: Int) {
        guard let fileHandle = fileHandle, page >= 0 && page < totalPages else { return }
        currentPage = page
        let start = page * pageSize
        let length = min(pageSize, fileSize - start)

        do {
            try fileHandle.seek(toOffset: UInt64(start))
            var newData = fileHandle.readData(ofLength: length)

            for (offset, edit) in edits {
                if offset >= start && offset < start + length {
                    newData[offset - start] = edit.newValue
                }
            }
            self.data = newData
        } catch {
            print("Error reading file: \(error)")
        }
    }

    func loadNextPage() {
        let nextPage = currentPage + 1
        if nextPage < totalPages {
            loadPage(nextPage)
        }
    }

    func loadPreviousPage() {
        let prevPage = currentPage - 1
        if prevPage >= 0 {
            loadPage(prevPage)
        }
    }

    var totalRowCount: Int {
        (fileSize + bytesPerRow - 1) / bytesPerRow
    }

    func applyEdit(offset: Int, newValue: UInt8) {
        guard let fileHandle = fileHandle, offset < fileSize else { return }
        
        var originalValue: UInt8
        if let existingEdit = edits[offset] {
            originalValue = existingEdit.originalValue
        } else {
            do {
                try fileHandle.seek(toOffset: UInt64(offset))
                originalValue = fileHandle.readData(ofLength: 1)[0]
            } catch {
                print("Failed to read original byte at offset \(offset): \(error)")
                return
            }
        }

        let edit = HexEdit(offset: offset, originalValue: originalValue, newValue: newValue)
        edits[offset] = edit
        let pageStart = currentPage * pageSize
        if offset >= pageStart && offset < pageStart + data.count {
            data[offset - pageStart] = newValue
        }
    }

    func revertEdit(offset: Int) {
        guard let edit = edits.removeValue(forKey: offset) else { return }

        let pageStart = currentPage * pageSize
        if offset >= pageStart && offset < pageStart + pageSize {
            let localOffset = offset - pageStart
            if localOffset < data.count {
                data[localOffset] = edit.originalValue
            }
        }
    }

    func revertAllEdits() {
        let offsetsToRevert = Array(edits.keys)
        for offset in offsetsToRevert {
            revertEdit(offset: offset)
        }
    }

    func generatePatchedData() throws -> Data {
        var data = try Data(contentsOf: fileURL)
        for (_, edit) in edits {
            data[edit.offset] = edit.newValue
        }
        return data
    }

    var currentPageStartOffset: Int {
        currentPage * pageSize
    }

    func isOffsetModified(_ offset: Int) -> Bool {
        return edits[offset] != nil
    }

    func searchForASCII(string: String) {
        guard let searchData = string.data(using: .ascii), !searchData.isEmpty else {
            self.foundOffsets = []
            return
        }

        var found: [Int] = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let fileHandle = self.fileHandle else { return }

            var searchOffset = 0
            while searchOffset < self.fileSize {
                let searchLength = min(self.pageSize, self.fileSize - searchOffset)
                do {
                    try fileHandle.seek(toOffset: UInt64(searchOffset))
                    let data = fileHandle.readData(ofLength: searchLength)
                    
                    var searchIndex = 0
                    while searchIndex < data.count {
                        if let range = data.range(of: searchData, options: [], in: searchIndex..<data.count) {
                            found.append(searchOffset + range.lowerBound)
                            searchIndex = range.upperBound
                        } else {
                            break
                        }
                    }
                } catch {
                    print("Error seeking or reading file during search: \(error)")
                    break
                }
                searchOffset += self.pageSize
            }

            DispatchQueue.main.async {
                self.foundOffsets = found
            }
        }
    }

}
