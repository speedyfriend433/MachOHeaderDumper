import SwiftUI

struct HexEditorView: View {
    @StateObject var hexViewModel: HexEditorViewModel
    @State private var showShareSheet = false
    @State private var patchedFileURL: URL?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private let columns: [GridItem] = Array(repeating: .init(.fixed(22)), count: 16)

    init(fileData: Data, fileURL: URL) {
        _hexViewModel = StateObject(wrappedValue: try! HexEditorViewModel(fileURL: fileURL))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(0..<hexViewModel.totalRowCount, id: \.self) { rowIndex in
                        HexEditorRow(
                            viewModel: hexViewModel,
                            rowIndex: rowIndex
                        )
                    }
                } header: {
                    HexEditorHeaderRow()
                        .background(.background)
                }
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .navigationTitle("Hex Editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportPatchedFile) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(hexViewModel.edits.isEmpty)
            }
        }
        .sheet(item: $patchedFileURL) { url in
            ShareSheet(activityItems: [url])
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func exportPatchedFile() {
        let patchedData = hexViewModel.generatePatchedData()
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "PatchedFile.bin"
        let tempURL = tempDir.appendingPathComponent(fileName)

        do {
            try patchedData.write(to: tempURL, options: .atomic)
            self.patchedFileURL = tempURL
        } catch {
            errorMessage = "Failed to write patched file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

struct HexEditorRow: View {
    @ObservedObject var viewModel: HexEditorViewModel
    let rowIndex: Int

    private var offset: Int {
        rowIndex * viewModel.bytesPerRow
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%08X", offset))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(0..<viewModel.bytesPerRow, id: \.self) { colIndex in
                    let byteOffset = offset + colIndex
                    if byteOffset < viewModel.data.count {
                        HexByteView(
                            viewModel: viewModel,
                            offset: byteOffset
                        )
                    } else {
                        Text("  ")
                    }
                }
            }
            Text(asciiRepresentation())
                .lineLimit(1)
        }
    }

    private func asciiRepresentation() -> String {
        var representation = ""
        for i in 0..<viewModel.bytesPerRow {
            let byteOffset = offset + i
            if byteOffset < viewModel.data.count {
                let byte = viewModel.data[byteOffset]
                representation += (isprint(Int32(byte)) != 0) ? String(UnicodeScalar(byte)) : "."
            }
        }
        return representation
    }
}

struct HexByteView: View {
    @ObservedObject var viewModel: HexEditorViewModel
    let offset: Int
    
    @State private var showEditPopover = false
    @State private var newHexValue: String = ""

    var isSelected: Bool {
        viewModel.selectedOffset == offset
    }

    var isModified: Bool {
        viewModel.isOffsetModified(offset)
    }

    var byteValue: UInt8 {
        viewModel.data[offset]
    }

    var body: some View {
        Text(String(format: "%02X", byteValue))
            .foregroundColor(isModified ? .blue : .primary)
            .background(isSelected ? Color.yellow.opacity(0.5) : Color.clear)
            .cornerRadius(2)
            .onTapGesture {
                viewModel.selectedOffset = offset
                newHexValue = String(format: "%02X", byteValue)
                showEditPopover = true
            }
            .popover(isPresented: $showEditPopover, arrowEdge: .bottom) {
                HexEditPopover(
                    currentHex: $newHexValue,
                    offset: offset
                ) { newByte in
                    viewModel.applyEdit(offset: offset, newValue: newByte)
                    showEditPopover = false
                }
            }
    }
}

struct HexEditorHeaderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Offset")
                .frame(width: 70, alignment: .leading)
            Text("00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")
                .layoutPriority(1)
            Text("ASCII")
        }
        .font(.caption.bold())
        .foregroundColor(.secondary)
        .padding(.horizontal, 5)
    }
}

struct HexEditPopover: View {
    @Binding var currentHex: String
    let offset: Int
    let onCommit: (UInt8) -> Void

    var body: some View {
        VStack {
            Text("Edit Byte at \(String(format: "0x%X", offset))")
                .font(.headline)
            
            TextField("Hex Value", text: $currentHex)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .multilineTextAlignment(.center)
                .onChange(of: currentHex) { newValue in
                    let filtered = newValue.uppercased().filter { "0123456789ABCDEF".contains($0) }
                    if filtered.count > 2 {
                        currentHex = String(filtered.prefix(2))
                    } else {
                        currentHex = filtered
                    }
                }
            
            Button("Done") {
                if let byteValue = UInt8(currentHex, radix: 16) {
                    onCommit(byteValue)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentHex.isEmpty || currentHex.count > 2)
        }
        .padding()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: Identifiable {
    public var id: String { self.absoluteString }
}
