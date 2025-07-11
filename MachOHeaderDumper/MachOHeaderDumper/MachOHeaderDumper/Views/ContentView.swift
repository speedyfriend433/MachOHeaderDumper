import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MachOViewModel()
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Bar
            HStack {
                if let fileURL = viewModel.parsedData?.fileURL {
                    Text(fileURL.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("No File Selected").font(.headline).foregroundColor(.gray)
                }
                Spacer()
                ControlsView(isLoading: viewModel.isLoading) { showFilePicker = true }
            }
            .padding(.horizontal).padding(.top, 10).padding(.bottom, 5)

            // MARK: - Status & Error
            StatusErrorView(
                isLoading: viewModel.isLoading,
                statusMessage: viewModel.statusMessage,
                errorMessage: viewModel.errorMessage,
                parsedDataIsAvailable: viewModel.parsedData != nil
            )
            .padding(.bottom, 5)

            Divider()

            // MARK: - Main Content: TabView
            TabView {
                NavigationView { DumpView(viewModel: viewModel) }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Dump", systemImage: "chevron.left.forwardslash.chevron.right") }

                NavigationView { StructureView(viewModel: viewModel) }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Structure", systemImage: "wrench.and.screwdriver.fill") }

                NavigationView {
                     if let parsed = viewModel.parsedData, let symbols = parsed.symbols, !symbols.isEmpty {
                         SymbolsView(symbols: symbols, dynamicInfo: parsed.dynamicSymbolInfo)
                             .navigationTitle("Symbols")
                     } else {
                         VStack { ContentUnavailableView(title: "No Symbols Found", description: "The symbol table might be missing or stripped.") }
                             .navigationTitle("Symbols")
                     }
                }
                .navigationViewStyle(.stack)
                .tabItem { Label("Symbols", systemImage: "function") }

                NavigationView { DynamicLinkerView(viewModel: viewModel) }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Dynamic", systemImage: "link") }
            }
            .accentColor(.blue)
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { url in viewModel.processURL(url) }
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
