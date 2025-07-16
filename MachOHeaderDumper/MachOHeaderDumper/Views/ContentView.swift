import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MachOViewModel()
    @State private var showFilePicker = false
    @State private var selectedTab: Tab = .dump // if you want to launch the app with hex edit tab, change it to .hexEditor

    enum Tab: Hashable {
        case dump, structure, symbols, dynamic, hexEditor
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Top Bar (File Name & Import Button)
            HStack {
                if let fileURL = viewModel.parsedData?.fileURL {
                    Text(fileURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No File Selected")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                Spacer()
                ControlsView(isLoading: viewModel.isLoading) {
                    showFilePicker = true
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 5)

            // MARK: - Status & Error Display Area
            StatusErrorView(
                isLoading: viewModel.isLoading,
                statusMessage: viewModel.statusMessage,
                errorMessage: viewModel.errorMessage,
                parsedDataIsAvailable: viewModel.parsedData != nil
            )
            .padding(.bottom, 5)

            Divider()

            // MARK: - Main Content: TabView
            TabView(selection: $selectedTab) {
                NavigationView {
                    DumpView(viewModel: viewModel)
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Dump", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(Tab.dump)

                NavigationView {
                    StructureView(viewModel: viewModel)
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Structure", systemImage: "wrench.and.screwdriver.fill") }
                .tag(Tab.structure)

                NavigationView {
                     if let parsed = viewModel.parsedData, let symbols = parsed.symbols, !symbols.isEmpty {
                         SymbolsView(symbols: symbols, dynamicInfo: parsed.dynamicSymbolInfo)
                             .navigationTitle("Symbols")
                     } else {
                         VStack {
                              ContentUnavailableView(title: "No Symbols Found", description: "The symbol table might be missing or stripped.")
                         }
                         .navigationTitle("Symbols")
                     }
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Symbols", systemImage: "function") }
                .tag(Tab.symbols)

                NavigationView {
                     DynamicLinkerView(viewModel: viewModel)
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Dynamic", systemImage: "link") }
                .tag(Tab.dynamic)
                
                NavigationView {
                     Group {
                         if let fileURL = viewModel.parsedData?.fileURL {
                             HexEditorView.InitializingView(fileURL: fileURL)
                         } else {
                             VStack {
                                 ContentUnavailableView(title: "No File Loaded", description: "Import a file to use the Hex Editor.")
                             }
                             .navigationTitle("Hex Editor")
                         }
                     }
                 }
                 .navigationViewStyle(.stack)
                 .tabItem { Label("Hex Edit", systemImage: "square.and.pencil") }
                .tag(Tab.hexEditor)

            }
            .accentColor(.blue)

        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { url in
                viewModel.processURL(url)
                selectedTab = .dump 
            }
        }
    }
}


// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
