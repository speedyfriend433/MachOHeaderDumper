//
//  ContentView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: Views/ContentView.swift (Correct Toggle Condition)

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MachOViewModel()
    @State private var showFilePicker = false
    @State private var selectedView: ViewType = .info

    // Correct Enum definition
    enum ViewType: String, CaseIterable, Identifiable {
        case objcDump = "ObjC Dump"
        case swiftDump = "Swift Dump"
        case info = "Info"
        case categories = "Categories"
        case loadCmds = "Load Cmds"
        case strings = "Strings"
        case funcStarts = "Func Starts"
        case symbols = "Symbols"
        case dyldInfo = "DyldInfo"
        case exports = "Exports"
        case selectorRefs = "Sel Refs"
        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                topBar()
                statusErrorDisplay().padding(.bottom, 5)
                // Use the corrected viewSelectorAndOptions below
                viewSelectorAndOptions()
                if viewModel.parsedData != nil && !viewModel.isLoading {
                    Divider().padding(.horizontal)
                }
                mainContentArea().layoutPriority(1)
            }
            .navigationTitle("MachO Dumper")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFilePicker) { DocumentPicker { url in viewModel.processURL(url) } }
            .onChange(of: viewModel.processingUpdateId) { _ in checkSelectedViewValidity() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - @ViewBuilder Functions for UI Sections

    // Top Bar: File Name + Import Button
    @ViewBuilder
    private func topBar() -> some View {
        HStack {
            if let fileURL = viewModel.parsedData?.fileURL {
                Text(fileURL.lastPathComponent)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                    .id("fileName_\(fileURL.path)")
            } else {
                Text("No File Selected").font(.headline).foregroundColor(.gray)
            }
            Spacer()
            // Directly use Button action
            Button { showFilePicker = true } label: { Label("Import File...", systemImage: "doc.badge.plus") }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 5)
    }

    // Status and Error Display
    @ViewBuilder
    private func statusErrorDisplay() -> some View {
        VStack(spacing: 4) {
            HStack {
                if viewModel.isLoading { ProgressView().scaleEffect(0.7) }
                Text(viewModel.statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                // Add demangler status back if desired - ensure DemanglerStatus enum is accessible
                 if viewModel.demanglerStatus != .idle {
                     Text(viewModel.demanglerStatus.description)
                          .font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                          .background(viewModel.demanglerStatus.color.opacity(0.2))
                          .foregroundColor(viewModel.demanglerStatus.color).cornerRadius(4)
                 }
            }

            if let errorMsg = viewModel.errorMessage {
                let isNoObjCMetaError = errorMsg.contains("No Objective-C")
                let errorColor: Color = (isNoObjCMetaError && viewModel.parsedData != nil) ? .orange : .red
                Text(errorMsg).font(.caption).foregroundColor(errorColor).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    // View Selector and Options
    @ViewBuilder
        private func viewSelectorAndOptions() -> some View {
            if let parsedData = viewModel.parsedData, !viewModel.isLoading {
                VStack(spacing: 5) {
                     Picker("View", selection: $selectedView) {
                         // Use CORRECTED enum cases for tags
                         if viewModel.objcHeaderOutput != nil { Text(ViewType.objcDump.rawValue).tag(ViewType.objcDump) }
                         if viewModel.swiftDumpOutput != nil { Text(ViewType.swiftDump.rawValue).tag(ViewType.swiftDump) }
                         Text(ViewType.info.rawValue).tag(ViewType.info)
                         if !viewModel.extractedCategories.isEmpty { Text(ViewType.categories.rawValue).tag(ViewType.categories) }
                         Text(ViewType.loadCmds.rawValue).tag(ViewType.loadCmds)
                         if !viewModel.foundStrings.isEmpty { Text(ViewType.strings.rawValue).tag(ViewType.strings) }
                         if !viewModel.functionStarts.isEmpty { Text(ViewType.funcStarts.rawValue).tag(ViewType.funcStarts) }
                         if parsedData.symbols?.isEmpty == false { Text(ViewType.symbols.rawValue).tag(ViewType.symbols) }
                         if viewModel.parsedDyldInfo != nil { Text(ViewType.dyldInfo.rawValue).tag(ViewType.dyldInfo) }
                         if viewModel.parsedDyldInfo?.exports.isEmpty == false { Text(ViewType.exports.rawValue).tag(ViewType.exports) }
                         if !viewModel.selectorReferences.isEmpty { Text(ViewType.selectorRefs.rawValue).tag(ViewType.selectorRefs) }
                     }
                     .pickerStyle(.menu)

                     // FIX: Check selectedView against the CORRECTED enum case .objcDump
                     if selectedView == .objcDump && viewModel.generatedHeader != nil {
                          Toggle("Show IVars", isOn: $viewModel.showIvarsInHeader)
                              .font(.caption)
                              .onChange(of: viewModel.showIvarsInHeader) { _ in if let url = viewModel.parsedData?.fileURL { viewModel.processURL(url) } }
                              .padding(.top, 2)
                     }
                }
                .padding(.horizontal)
                .padding(.bottom, 5)
            } else { EmptyView() }
        }

    // Main Content Area using the Switch
    @ViewBuilder
    private func mainContentArea() -> some View {
        // Removed the outer Group and AnyView from previous attempts
        if viewModel.isLoading {
            VStack { Spacer(); ProgressView("Processing..."); Spacer() }
        } else if let parsed = viewModel.parsedData {
            // The switch directly returns the appropriate view
            switch selectedView {
            //case .header: if let txt = viewModel.generatedHeader { HeaderDisplayView(headerText: txt) } else { ContentUnavailableView(title: "ObjC Header Not Available") }
            //case .swiftTypes: if !viewModel.extractedSwiftTypes.isEmpty { SwiftTypesView(types: viewModel.extractedSwiftTypes) } else { ContentUnavailableView(title: "Swift Types Not Available") }
            case .info: InfoView(parsedData: parsed)
            case .categories: if !viewModel.extractedCategories.isEmpty { CategoriesView(categories: viewModel.extractedCategories) } else { ContentUnavailableView(title: "No Categories Found") }
            case .loadCmds: LoadCommandsView(loadCommands: parsed.loadCommands)
            case .strings: if !viewModel.foundStrings.isEmpty { StringsView(strings: viewModel.foundStrings) } else { ContentUnavailableView(title: "No Strings Found") }
            case .funcStarts: if !viewModel.functionStarts.isEmpty { FunctionStartsView(starts: viewModel.functionStarts) } else { ContentUnavailableView(title: "No Function Starts Found") }
            case .symbols: if let syms = parsed.symbols, !syms.isEmpty { SymbolsView(symbols: syms, dynamicInfo: parsed.dynamicSymbolInfo) } else { ContentUnavailableView(title: "No Symbols Found") }
            case .dyldInfo: if let dyld = viewModel.parsedDyldInfo { DyldInfoView(info: dyld) } else { ContentUnavailableView(title: "Dyld Info Not Available") }
            case .exports: if let exports = viewModel.parsedDyldInfo?.exports, !exports.isEmpty { ExportsView(exports: exports, imageBase: parsed.baseAddress) } else { ContentUnavailableView(title: "Exports Not Available") }
            case .selectorRefs: if !viewModel.selectorReferences.isEmpty { SelectorRefsView(refs: viewModel.selectorReferences) } else { ContentUnavailableView(title: "No Selector References Found") }
            case .objcDump:   // Correct case
                                if let txt = viewModel.objcHeaderOutput, !txt.starts(with:"// Dump failed") { HeaderDisplayView(headerText: txt) } else { ContentUnavailableView(title: "ObjC Dump Not Available") }
                            case .swiftDump:  // Correct case
                                if let txt = viewModel.swiftDumpOutput, !txt.starts(with:"// Dump failed") { HeaderDisplayView(headerText: txt) } else { ContentUnavailableView(title: "Swift Dump Not Available") }
                
            }
        } else { // Idle or fatal error
            if viewModel.errorMessage == nil { ContentUnavailableView(title: "No File Loaded", description: "...") }
            else { ContentUnavailableView(title: "Parsing Failed", description: viewModel.errorMessage ?? "...").foregroundColor(.red) }
        }
    }

    // Helper function to check validity
    private func checkSelectedViewValidity() {
        var needsReset = false
        guard viewModel.parsedData != nil else { return } // No checks needed if no data

        // Switch uses CORRECTED enum type
                switch selectedView {
                    case .objcDump:   if viewModel.generatedHeader == nil || (viewModel.generatedHeader?.starts(with:"// Dump failed") ?? false) { needsReset = true }
                    case .swiftDump:  if viewModel.swiftDumpOutput == nil || (viewModel.swiftDumpOutput?.starts(with:"// Dump failed") ?? false) { needsReset = true }
                    case .symbols:     if viewModel.parsedData?.symbols?.isEmpty ?? true { needsReset = true }
                    case .dyldInfo:    if viewModel.parsedDyldInfo == nil { needsReset = true }
                    case .exports:     if viewModel.parsedDyldInfo?.exports.isEmpty ?? true { needsReset = true }
                    case .categories:  if viewModel.extractedCategories.isEmpty { needsReset = true }
                    case .strings:     if viewModel.foundStrings.isEmpty { needsReset = true }
                    case .funcStarts:  if viewModel.functionStarts.isEmpty { needsReset = true }
                    case .selectorRefs:if viewModel.selectorReferences.isEmpty { needsReset = true }
                    case .info, .loadCmds: break
                    // No other cases should exist if enum is correct
                }

        if needsReset {
            print("Resetting selected view from \(selectedView) to .info")
            selectedView = .info
        }
    }

} // --- END ContentView struct ---

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
}
