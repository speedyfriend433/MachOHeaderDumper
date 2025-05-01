//
//  ContentView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: Views/ContentView.swift (Enhanced UI - Corrected Braces & Structure)

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
        case loadCmds = "Load Cmds"
        case strings = "Strings"
        case symbols = "Symbols"
        case dyldInfo = "DyldInfo"
        case exports = "Exports"
        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) { // Use spacing 0 for tighter layout control

                // MARK: - Top Bar (File Name & Import Button)
                HStack {
                    // Display current file name if available
                    if let fileURL = viewModel.parsedData?.fileURL {
                        Text(fileURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .id("fileName_\(fileURL.path)") // Add ID for updates
                    } else {
                        Text("No File Selected")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    // Use ControlsView struct directly
                    ControlsView(isLoading: viewModel.isLoading) { showFilePicker = true }
                }
                .padding(.horizontal)
                .padding(.top, 10) // Add consistent padding
                .padding(.bottom, 5)

                // MARK: - Status & Error Display Area
                // Use StatusErrorView struct directly
                StatusErrorView(
                    isLoading: viewModel.isLoading,
                    statusMessage: viewModel.statusMessage,
                    errorMessage: viewModel.errorMessage,
                    parsedDataIsAvailable: viewModel.parsedData != nil,
                    demanglerStatus: viewModel.demanglerStatus
                )
                .padding(.bottom, 5) // Padding below status

                // MARK: - View Selector & Conditional Options
                // Use ViewSelectorView struct directly if data parsed and not loading
                if viewModel.parsedData != nil && !viewModel.isLoading {
                    ViewSelectorView(viewModel: viewModel, selectedView: $selectedView)
                        .padding(.bottom, 5) // Padding below selector
                    Divider() // Show divider only when selector is visible
                } else if !viewModel.isLoading && viewModel.parsedData == nil {
                    // Optionally add a smaller divider or just rely on spacing
                    // Divider().padding(.horizontal)
                }


                // MARK: - Main Content Area
                // Use MainContentView struct directly
                MainContentView(
                     viewModel: viewModel,
                     selectedView: selectedView
                )
                .layoutPriority(1) // Allow content area to expand

            } // End Top Level VStack
            // Apply modifiers to the VStack
            .navigationTitle("MachO Dumper")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFilePicker) { DocumentPicker { url in viewModel.processURL(url) } }
            // Use the single consolidated onChange modifier
            .onChange(of: viewModel.processingUpdateId) { _ in checkSelectedViewValidity() }
            .onChange(of: viewModel.foundStrings) { _ in // Add onChange for strings
                              if viewModel.foundStrings.isEmpty && selectedView == .strings {
                                  selectedView = .info // Fallback if strings disappear
                              }
                         }

        } // End NavigationView
        // Apply navigationViewStyle *outside* the NavigationView
        .navigationViewStyle(.stack)

    } // End body


    // --- Helper function to consolidate checks ---
    // Keep this inside ContentView struct
    private func checkSelectedViewValidity() {
        var needsReset = false
        switch selectedView {
        case .header:
            if viewModel.generatedHeader == nil { needsReset = true }
        case .symbols:
            if viewModel.parsedData?.symbols?.isEmpty ?? true { needsReset = true }
        case .dyldInfo:
            if viewModel.parsedDyldInfo == nil { needsReset = true }
        case .strings: 
            if viewModel.foundStrings.isEmpty { needsReset = true }
        case .exports:
            if viewModel.parsedDyldInfo == nil || (viewModel.parsedDyldInfo?.exports.isEmpty ?? true) { needsReset = true }
        case .swiftTypes:
            if viewModel.extractedSwiftTypes.isEmpty { needsReset = true }
        case .info, .loadCmds:
            break // Always valid if parsedData exists
        }

        if needsReset {
            print("Resetting selected view from \(selectedView) to .info")
            selectedView = .info
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
