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

    let fileURL: URL
    let originalData: Data
    let pageSize: Int = 4096
    let bytesPerRow: Int = 16

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.originalData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        self.data = self.originalData
    }

    var totalRowCount: Int {
        (data.count + bytesPerRow - 1) / bytesPerRow
    }

    func applyEdit(offset: Int, newValue: UInt8) {
        guard offset < data.count else { return }
        let originalValue = edits[offset]?.originalValue ?? originalData[offset]
        let edit = HexEdit(offset: offset, originalValue: originalValue, newValue: newValue)

        data[offset] = newValue
        edits[offset] = edit
    }

    func revertEdit(offset: Int) {
        guard let edit = edits[offset] else { return }
        data[offset] = edit.originalValue
        edits.removeValue(forKey: offset)
    }

    func generatePatchedData() -> Data {
        return self.data
    }

    func isOffsetModified(_ offset: Int) -> Bool {
        return edits[offset] != nil
    }
}
