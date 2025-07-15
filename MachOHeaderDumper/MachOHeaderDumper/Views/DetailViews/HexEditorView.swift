import SwiftUI
import UniformTypeIdentifiers

struct HexEditorView: View {
    @StateObject var hexViewModel: HexEditorViewModel
    @State private var isExporting = false
    @State private var document: PatchedFileDocument?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var goToAddressString = ""
    @State private var searchASCIIString = ""
    @State private var highlightedOffset: Int? = nil
    @State private var scrollToID: Int?
    @State private var showSettings = false
    @State private var showSearchControls = true
    @State private var fontSize: CGFloat = 12



    init(fileData: Data, fileURL: URL) {
        _hexViewModel = StateObject(wrappedValue: try! HexEditorViewModel(fileURL: fileURL))
    }

    var body: some View {
        VStack {
            if showSearchControls {
                VStack {
                    HStack {
                        TextField("Go to Address (Hex)", text: $goToAddressString)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, design: .monospaced))
                        
                        Button("Go") {
                            if let address = Int(goToAddressString, radix: 16) {
                                let rowIndex = address / hexViewModel.bytesPerRow
                                scrollToID = rowIndex
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack {
                        TextField("Search ASCII String", text: $searchASCIIString)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, design: .monospaced))
                        
                        Button("Search") {
                            hexViewModel.searchForASCII(string: searchASCIIString)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                        Section {
                            ForEach(0..<hexViewModel.totalRowCount, id: \.self) { rowIndex in
                                HexEditorRow(
                                    viewModel: hexViewModel,
                                    rowIndex: rowIndex
                                )
                                .id(rowIndex)
                                .frame(height: fontSize + 8)
                                .onAppear {
                                    let rowOffset = rowIndex * hexViewModel.bytesPerRow
                                    let currentPageStart = hexViewModel.currentPage * hexViewModel.pageSize
                                    let currentPageEnd = currentPageStart + hexViewModel.pageSize
                                    let threshold = hexViewModel.pageSize / 4
                                    if rowOffset > currentPageEnd - threshold {
                                        hexViewModel.loadNextPage()
                                    } else if rowOffset < currentPageStart + threshold && hexViewModel.currentPage > 0 {
                                        hexViewModel.loadPreviousPage()
                                    }
                                }
                            }
                        } header: {
                            HexEditorHeaderRow(viewModel: hexViewModel)
                                .background(.background)
                        }
                    }
                    .id(hexViewModel.bytesPerRow)
                }
                .onChange(of: scrollToID) { newID in
                    if let newID = newID {
                        withAnimation {
                            scrollProxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
                .onChange(of: hexViewModel.foundOffsets) { foundOffsets in
                    if let firstOffset = foundOffsets.first {
                        hexViewModel.highlightedOffset = firstOffset
                        let rowIndex = firstOffset / hexViewModel.bytesPerRow
                        scrollToID = rowIndex
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            hexViewModel.highlightedOffset = nil
                        }
                    }
                }
            }
            if showSettings {
                HexEditorSettingsView(viewModel: hexViewModel, fontSize: $fontSize)
                    .padding()
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .navigationTitle("Hex Editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showSearchControls.toggle() }) {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                    }

                    Button(action: { hexViewModel.revertAllEdits() }) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(hexViewModel.edits.isEmpty)
                    
                    Button(action: exportPatchedFile) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(hexViewModel.edits.isEmpty)
                }
            }
        }
        .fileExporter(isPresented: $isExporting, document: document, contentType: .data, defaultFilename: hexViewModel.fileURL.lastPathComponent + "-patched") {
            result in
            switch result {
            case .success(let url):
                print("Saved to \(url)")
            case .failure(let error):
                errorMessage = "Failed to export file: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func exportPatchedFile() {
        do {
            let patchedData = try hexViewModel.generatePatchedData()
            self.document = PatchedFileDocument(data: patchedData)
            self.isExporting = true
        } catch {
            errorMessage = "Failed to create patched file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

struct HexEditorSettingsView: View {
    @ObservedObject var viewModel: HexEditorViewModel
    @Binding var fontSize: CGFloat

    var body: some View {
        VStack {
            Stepper("Bytes per Row: \(viewModel.bytesPerRow)", value: $viewModel.bytesPerRow, in: 4...32, step: 4)
            
            HStack {
                Text("Font Size")
                Slider(value: $fontSize, in: 8...24, step: 1)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct PatchedFileDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.data]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct HexEditorRow: View {
    @ObservedObject var viewModel: HexEditorViewModel
    let rowIndex: Int

    private var offset: Int {
        rowIndex * viewModel.bytesPerRow
    }

    private var rowData: Data {
        let start = offset - viewModel.currentPageStartOffset
        let end = min(start + viewModel.bytesPerRow, viewModel.data.count)
        if start < 0 || start >= viewModel.data.count { return Data() }
        return viewModel.data.subdata(in: start..<end)
    }

    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                addressView
                hexView
                    .frame(maxWidth: .infinity, alignment: .leading)
                asciiView
            }
            HStack(spacing: 8) {
                addressView
                hexView
            }
        }
    }

    private var addressView: some View {
        Text(String(format: "%08X", offset))
            .foregroundColor(.secondary)
            .frame(width: 70, alignment: .leading)
    }

    private var hexView: some View {
        HStack(spacing: 4) {
            ForEach(0..<rowData.count, id: \.self) { index in
                let byteOffset = offset + index
                HexByteView(
                    viewModel: viewModel,
                    offset: byteOffset
                )
            }
            if rowData.count < viewModel.bytesPerRow {
                ForEach(0..<(viewModel.bytesPerRow - rowData.count), id: \.self) { _ in
                    Text("  ")
                }
            }
        }
        .frame(minWidth: CGFloat(viewModel.bytesPerRow) * 24, alignment: .leading)
    }

    private var asciiView: some View {
        Text(asciiRepresentation())
            .lineLimit(1)
            .frame(width: CGFloat(viewModel.bytesPerRow) * 8, alignment: .leading)
    }

    private func asciiRepresentation() -> String {
        var representation = ""
        for byte in rowData {
            representation += (isprint(Int32(byte)) != 0) ? String(UnicodeScalar(byte)) : "."
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

    var isHighlighted: Bool {
        viewModel.highlightedOffset == offset
    }

    var isModified: Bool {
        viewModel.isOffsetModified(offset)
    }

    var byteValue: UInt8? {
        let localOffset = offset - viewModel.currentPageStartOffset
        guard localOffset >= 0 && localOffset < viewModel.data.count else { return nil }
        return viewModel.data[localOffset]
    }

    var body: some View {
        Group {
            if let byteValue = byteValue {
                Text(String(format: "%02X", byteValue))
                    .foregroundColor(isModified ? .blue : .primary)
                    .background(isHighlighted ? Color.yellow.opacity(0.7) : (isSelected ? Color.yellow.opacity(0.5) : Color.clear))
                    .cornerRadius(2)
                    .onTapGesture {
                        viewModel.selectedOffset = offset
                        newHexValue = String(format: "%02X", byteValue)
                        showEditPopover = true
                    }
                    .popover(isPresented: $showEditPopover) {
                        HexEditPopover(
                            currentHex: $newHexValue,
                            offset: offset
                        ) { newByte in
                            viewModel.applyEdit(offset: offset, newValue: newByte)
                            showEditPopover = false
                        }
                    }
            } else {
                Text("  ")
            }
        }
    }
}

struct HexEditorHeaderRow: View {
    @ObservedObject var viewModel: HexEditorViewModel
    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                Text("Offset")
                    .frame(width: 70, alignment: .leading)
                hexHeader
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("ASCII")
                    .frame(width: CGFloat(viewModel.bytesPerRow) * 8, alignment: .leading)
            }

            HStack(spacing: 8) {
                Text("Offset")
                    .frame(width: 70, alignment: .leading)
                hexHeader
            }
        }
        .font(.caption.bold())
        .foregroundColor(.secondary)
        .padding(.horizontal, 5)
    }

    private var hexHeader: some View {
        let header = (0..<viewModel.bytesPerRow).map { String(format: "%02X", $0) }.joined(separator: " ")
        return Text(header)
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
