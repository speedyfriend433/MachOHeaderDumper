import SwiftUI
import UniformTypeIdentifiers

struct PatchedFileDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.data]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct HexEditorView: View {
    @StateObject var hexViewModel: HexEditorViewModel
    @State private var isExporting = false
    @State private var document: PatchedFileDocument?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var goToAddressString = ""
    @State private var showSettings = false
    @State private var showSearchPopover = false
    @State private var fontSize: CGFloat = 12
    @State private var searchType: SearchType = .hex
    @State private var isEditingByte = false
    @State private var editingOffset: Int?
    @State private var editingValueString = ""
    @State private var highlightedOffset: Int? = nil
    @State private var highlightedGoToOffset: Int? = nil
    
    struct InitializingView: View {
        let fileURL: URL
        @State private var result: Result<HexEditorViewModel, Error>? = nil
        
        var body: some View {
            Group {
                switch result {
                case .success(let viewModel):
                    HexEditorView(viewModel: viewModel)
                case .failure(let error):
                    ContentUnavailableView(
                        title: "Failed to Open File",
                        description: error.localizedDescription,
                        systemImage: "xmark.octagon.fill"
                    )
                    .foregroundColor(.red)
                case nil:
                    ProgressView("Opening File...").onAppear {
                        do {
                            let viewModel = try HexEditorViewModel(fileURL: fileURL)
                            self.result = .success(viewModel)
                        } catch {
                            self.result = .failure(error)
                        }
                    }
                }
            }
        }
    }
    
    init(fileURL: URL) {
        let viewModel: HexEditorViewModel
        do {
            viewModel = try HexEditorViewModel(fileURL: fileURL)
        } catch {
            fatalError("This initializer should be called via InitializingView to handle errors.")
        }
        _hexViewModel = StateObject(wrappedValue: viewModel)
    }
    
    private init(viewModel: HexEditorViewModel) {
        _hexViewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
            
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<hexViewModel.totalRowCount, id: \.self) { rowIndex in
                            HexEditorRow(
                                viewModel: hexViewModel,
                                rowIndex: rowIndex,
                                highlightedOffset: $highlightedOffset,
                                highlightedGoToOffset: $highlightedGoToOffset,
                                editingOffset: $editingOffset,
                                editingValueString: $editingValueString,
                                isEditingByte: $isEditingByte
                            )
                            .frame(height: fontSize + 8)
                            .onAppear { hexViewModel.rowDidAppear(rowIndex: rowIndex) }
                        }
                    }
                    .id(hexViewModel.bytesPerRow)
                }
                .onChange(of: hexViewModel.scrollToID) { newID in
                    if let newID = newID {
                        print("Scrolling to row index: \(newID)")
                        withAnimation { scrollProxy.scrollTo(newID, anchor: .center) }
                        if let selected = hexViewModel.selectedOffset {
                            self.highlightedOffset = selected
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.highlightedOffset = nil
                            }
                        }
                        hexViewModel.scrollToID = nil
                    }
                }
            }
        .font(.system(size: fontSize, design: .monospaced))
             .navigationTitle("Hex Editor") // Hex Editor + file name => \(hexViewModel.fileURL.lastPathComponent)?
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                Button(action: { showSearchPopover.toggle() }) {
                    Label("Search", systemImage: "magnifyingglass")
                }

                Button(action: { showSettings.toggle() }) { 
                    Label("Settings", systemImage: "gear")
                }
                
                Button(action: { hexViewModel.revertAllEdits() }) { 
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .disabled(hexViewModel.edits.isEmpty)
                
                Button(action: { exportPatchedFile() }) { 
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(hexViewModel.edits.isEmpty)
         }
         .sheet(isPresented: $showSettings) {
            HexEditorSettingsView(viewModel: hexViewModel, fontSize: $fontSize)
        }
        .popover(isPresented: $showSearchPopover, arrowEdge: .top) {
            SearchControlsView(
                goToAddressString: $goToAddressString,
                searchType: $searchType,
                searchText: $hexViewModel.searchText,
                onGo: { address in
                    let rowIndex = address / hexViewModel.bytesPerRow
                    hexViewModel.scrollToID = rowIndex
                    self.highlightedGoToOffset = address
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.highlightedGoToOffset = nil
                    }
                    showSearchPopover = false
                },
                onSearch: { searchText, searchType in
                    hexViewModel.search(searchText: searchText, searchType: searchType)
                    showSearchPopover = false
                }
            )
            .frame(minWidth: 300, idealWidth: 400)
            .padding()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .data,
            defaultFilename: hexViewModel.fileURL.lastPathComponent + ".patched"
        ) { result in
            switch result {
            case .success(let url):
                print("Successfully exported to \(url.lastPathComponent)")
            case .failure(let error):
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { showErrorAlert = false }
        } message: {
            Text(errorMessage)
        }
        .alert("Edit Byte", isPresented: $isEditingByte, actions: {
            TextField("Hex Value", text: $editingValueString)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            
            Button("Save") {
                if let offset = editingOffset,
                   let newValue = UInt8(editingValueString, radix: 16) {
                    hexViewModel.applyEdit(offset: offset, newValue: newValue)
                }
            }
            Button("Cancel", role: .cancel) { }
        }, message: {
            Text("Enter a new 8-bit hex value (00-FF) for offset \(String(format: "%08X", editingOffset ?? 0))")
        })
    }

    private func exportPatchedFile() {
        Task {
            do {
                let patchedData = try await hexViewModel.generatePatchedData()
                self.document = PatchedFileDocument(data: patchedData)
                self.isExporting = true
            } catch {
                errorMessage = "Failed to create patched file: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Byte View (for interaction)

struct HexByteView: View {
    let byte: UInt8
    let isModified: Bool
    let isHighlighted: Bool
    let isGoToHighlighted: Bool

    var body: some View {
        Text(String(format: "%02X", byte))
            .foregroundColor(isModified ? .blue : .primary)
            .background(
                ZStack {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.yellow)
                            .transition(.opacity.animation(.easeInOut(duration: 1.0)))
                    }
                    if isGoToHighlighted {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .transition(.opacity.animation(.easeInOut(duration: 1.0)))
                    }
                }
            )
    }
}

// MARK: - Row View (Heavily Optimized)

struct HexEditorRow: View {
    @ObservedObject var viewModel: HexEditorViewModel
    let rowIndex: Int
    @Binding var highlightedOffset: Int?
    @Binding var highlightedGoToOffset: Int?
    @Binding var editingOffset: Int?
    @Binding var editingValueString: String
    @Binding var isEditingByte: Bool


    private var offset: Int {
        rowIndex * viewModel.bytesPerRow
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%08X", offset))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<viewModel.bytesPerRow, id: \.self) { colIndex in
                    let absoluteOffset = offset + colIndex
                    
                    if let byte = viewModel.byte(at: absoluteOffset) {
                        HexByteView(
                            byte: byte,
                            isModified: viewModel.isOffsetModified(absoluteOffset),
                            isHighlighted: highlightedOffset == absoluteOffset,
                            isGoToHighlighted: highlightedGoToOffset == absoluteOffset
                        )
                        .onTapGesture {
                            editingOffset = absoluteOffset
                            editingValueString = String(format: "%02X", byte)
                            isEditingByte = true
                        }
                    } else {
                        Text("--")
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(0..<viewModel.bytesPerRow, id: \.self) { colIndex in
                    let absoluteOffset = offset + colIndex
                    
                    if let byte = viewModel.byte(at: absoluteOffset) {
                         Text(isprint(Int32(byte)) != 0 ? String(UnicodeScalar(byte)) : ".")
                            .foregroundColor(viewModel.isOffsetModified(absoluteOffset) ? .blue : .primary)
                    } else {
                         Text(" ")
                    }
                }
            }
            .frame(width: CGFloat(viewModel.bytesPerRow) * 9, alignment: .leading)
        }
    }
}

struct SearchControlsView: View {
    @Binding var goToAddressString: String
    @Binding var searchType: SearchType
    @Binding var searchText: String
    
    var onGo: (Int) -> Void
    var onSearch: (String, SearchType) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Find & Navigate").font(.headline)
            
            VStack {
                HStack {
                    TextField("Go to Address (Hex)", text: $goToAddressString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))

                    Button("Go") {
                        let addressString = goToAddressString.hasPrefix("0x") ? String(goToAddressString.dropFirst(2)) : goToAddressString
                        if let address = Int(addressString, radix: 16) {
                            onGo(address)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(goToAddressString.isEmpty)
                }
            }
            
            VStack {
                Picker("Search Type", selection: $searchType) {
                    Text("Hex").tag(SearchType.hex)
                    Text("ASCII").tag(SearchType.ascii)
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField("Search Term", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit { onSearch(searchText, searchType) }

                    Button("Search") {
                        onSearch(searchText, searchType)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Supporting UI Components



struct HexEditorSettingsView: View {
    @ObservedObject var viewModel: HexEditorViewModel
    @Binding var fontSize: CGFloat
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Display") {
                    Stepper("Bytes per Row: \(viewModel.bytesPerRow)", value: $viewModel.bytesPerRow, in: 4...32, step: 4)
                    
                    HStack {
                        Text("Font Size: \(Int(fontSize))")
                        Slider(value: $fontSize, in: 8...24, step: 1)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
