//
//  ContentView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: Views/ContentView.swift (Isolate by replacing MainContentView call)

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MachOViewModel()
    @State private var showFilePicker = false
    @State private var selectedView: ViewType = .info

    // Keep Enum definition
    enum ViewType: String, CaseIterable, Identifiable {
        case header = "ObjC Header"
        case swiftTypes = "Swift Types"
        case info = "Info"
        case categories = "Categories" // Added
        case loadCmds = "Load Cmds"
        case strings = "Strings"       // Added
        case funcStarts = "Func Starts" // Added
        case symbols = "Symbols"
        case dyldInfo = "DyldInfo"
        case exports = "Exports"
        case selectorRefs = "Sel Refs" // Added
        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) { // Use spacing 0

                // Top Bar
                HStack {
                    if let fileURL = viewModel.parsedData?.fileURL { Text(fileURL.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle).id("fileName_\(fileURL.path)") }
                    else { Text("No File Selected").font(.headline).foregroundColor(.gray) }
                    Spacer()
                    ControlsView(isLoading: viewModel.isLoading) { showFilePicker = true }
                }
                .padding(.horizontal).padding(.top, 10).padding(.bottom, 5)

                // Status & Error
                StatusErrorView(isLoading: viewModel.isLoading, statusMessage: viewModel.statusMessage, errorMessage: viewModel.errorMessage, parsedDataIsAvailable: viewModel.parsedData != nil, demanglerStatus: viewModel.demanglerStatus)
                .padding(.bottom, 5)

                // View Selector
                if viewModel.parsedData != nil && !viewModel.isLoading {
                    ViewSelectorView(viewModel: viewModel, selectedView: $selectedView)
                        .padding(.bottom, 5)
                    Divider()
                } else if !viewModel.isLoading && viewModel.parsedData == nil {
                    // Divider() // Optional divider
                }

                /*// --- MAIN CONTENT AREA - TEMPORARILY REPLACED ---
                Spacer() // Use Spacer to push placeholder text
                Text("Main Content Placeholder")
                    .foregroundColor(.orange) // Make it obvious
                Spacer()
                // --- END REPLACEMENT ---*/
                // --- RESTORE MainContentView ---
                                MainContentView(
                                     viewModel: viewModel,
                                     selectedView: selectedView
                                )
                                .layoutPriority(1) // Allow content area to expand
                                // --- END RESTORE ---

            } // End Top Level VStack
            .navigationTitle("MachO Dumper")
                        .navigationBarTitleDisplayMode(.inline)
                        .sheet(isPresented: $showFilePicker) { DocumentPicker { url in viewModel.processURL(url) } }
                        // --- ENSURE ONLY THIS onChange REMAINS for view validity ---
                        .onChange(of: viewModel.processingUpdateId) { _ in
                            // Perform all validity checks *after* the processing ID changes
                            checkSelectedViewValidity()
                        }
            .onChange(of: viewModel.foundStrings) { _ in // Add onChange for strings
                              if viewModel.foundStrings.isEmpty && selectedView == .strings {
                                  selectedView = .info // Fallback if strings disappear
                              }
                         }
            .onChange(of: viewModel.functionStarts) { _ in // Add onChange
                              if viewModel.functionStarts.isEmpty && selectedView == .funcStarts {
                                  selectedView = .info
                              }
                         }
            .onChange(of: viewModel.selectorReferences) { _ in // Add onChange
                              if viewModel.selectorReferences.isEmpty && selectedView == .selectorRefs {
                                  selectedView = .info
                              }
                         }
            /*.onChange(of: viewModel.extractedCategories) { _ in // Add onChange
                              if viewModel.extractedCategories.isEmpty && selectedView == .categories {
                                  selectedView = .info
                              }
                         }
                        */
        } // End NavigationView
        // Apply navigationViewStyle *outside* the NavigationView
        .navigationViewStyle(.stack)

    } // End body


    // --- Helper function to consolidate checks ---
    // Keep this inside ContentView struct
    private func checkSelectedViewValidity() {
        var needsReset = false
        guard viewModel.parsedData != nil else {
            print("checkSelectedViewValidity called but parsedData is nil, skipping checks.")
                         return
                    }
        switch selectedView {
                case .header:      if viewModel.generatedHeader == nil { needsReset = true }
                case .swiftTypes:  if viewModel.extractedSwiftTypes.isEmpty { needsReset = true }
                case .symbols:     if viewModel.parsedData?.symbols?.isEmpty ?? true { needsReset = true }
                case .dyldInfo:    if viewModel.parsedDyldInfo == nil { needsReset = true }
                case .exports:     if viewModel.parsedDyldInfo?.exports.isEmpty ?? true { needsReset = true }
                case .categories:  if viewModel.extractedCategories.isEmpty { needsReset = true }
                case .strings:     if viewModel.foundStrings.isEmpty { needsReset = true }
                case .funcStarts:  if viewModel.functionStarts.isEmpty { needsReset = true }
                case .selectorRefs:if viewModel.selectorReferences.isEmpty { needsReset = true }
                case .info, .loadCmds: break // Always valid
                }

                if needsReset {
                    print("Resetting selected view from \(selectedView) to .info because its data is unavailable.")
                    selectedView = .info
                } else {
                     print("Selected view \(selectedView) is still valid.")
                }
            }

} // --- END ContentView struct --- (Ensure this is the final closing brace for the struct)

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
}
