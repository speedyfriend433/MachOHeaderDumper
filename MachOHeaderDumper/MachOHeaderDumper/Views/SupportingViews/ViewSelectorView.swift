//
//  ViewSelectorView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/SupportingViews/ViewSelectorView.swift

import SwiftUI

struct ViewSelectorView: View {
    @ObservedObject var viewModel: MachOViewModel
    @Binding var selectedView: ContentView.ViewType

    // Helper to get available view types based on current data
    private var availableViewTypes: [ContentView.ViewType] {
        var types: [ContentView.ViewType] = []
        if viewModel.generatedHeader != nil { types.append(.header) }
        if !viewModel.extractedSwiftTypes.isEmpty { types.append(.swiftTypes) }
        types.append(.info) // Always available if parsed
        types.append(.loadCmds) // Always available if parsed
        if viewModel.parsedData?.symbols?.isEmpty == false { types.append(.symbols) }
        if viewModel.parsedDyldInfo != nil { types.append(.dyldInfo) } // Show even if empty? Or check counts?
        if viewModel.parsedDyldInfo?.exports.isEmpty == false { types.append(.exports) }
        if !viewModel.foundStrings.isEmpty { types.append(.strings) }
        if !viewModel.functionStarts.isEmpty { types.append(.funcStarts) }
        if !viewModel.selectorReferences.isEmpty { types.append(.selectorRefs) }
        if !viewModel.extractedCategories.isEmpty { Text(ContentView.ViewType.categories.rawValue).tag(ContentView.ViewType.categories) }
        return types
    }

    var body: some View {
        Group {
            // Only show if data is parsed and not loading
            if viewModel.parsedData != nil && !viewModel.isLoading {
                // Use HStack for Picker Label and optional Toggle
                HStack {
                    // --- MENU PICKER ---
                    Picker("View", selection: $selectedView) {
                        // Dynamically populate options based on available data
                        ForEach(availableViewTypes) { viewType in
                             Text(viewType.rawValue).tag(viewType)
                        }
                    }
                    .pickerStyle(.menu) // Use dropdown menu style
                    // Optional: Apply specific styling like button border
                    // .buttonStyle(.bordered)
                    // .controlSize(.small)

                    Spacer() // Push toggle to the right if visible

                    // Conditional Ivar Toggle (Show only when Header is selected)
                    if selectedView == .header && viewModel.generatedHeader != nil {
                        Toggle("Show IVars", isOn: $viewModel.showIvarsInHeader)
                            .font(.caption)
                            .fixedSize() // Prevent toggle from taking too much space
                            .onChange(of: viewModel.showIvarsInHeader) { _ in
                                if let url = viewModel.parsedData?.fileURL {
                                    viewModel.processURL(url)
                                }
                            }
                    }
                }
                .padding(.horizontal) // Apply padding to the HStack
                .padding(.bottom, 5) // Keep padding below this row

            } else {
                EmptyView() // Don't show anything if no data/loading
            }
        } // End Group
    }
}
        
        /*Group {
            if let parsedData = viewModel.parsedData, !viewModel.isLoading {
                
                VStack(spacing: 5) {
                    Picker("View", selection: $selectedView) {
                    if viewModel.generatedHeader != nil {
                        Text(ContentView.ViewType.header.rawValue).tag(ContentView.ViewType.header) };
                    if !viewModel.extractedSwiftTypes.isEmpty {
                        Text(ContentView.ViewType.swiftTypes.rawValue).tag(ContentView.ViewType.swiftTypes) }; Text(ContentView.ViewType.info.rawValue).tag(ContentView.ViewType.info); Text(ContentView.ViewType.loadCmds.rawValue).tag(ContentView.ViewType.loadCmds);
                    if parsedData.symbols?.isEmpty == false {
                        Text(ContentView.ViewType.symbols.rawValue).tag(ContentView.ViewType.symbols) };
                    if !viewModel.foundStrings.isEmpty {
                        Text(ContentView.ViewType.strings.rawValue).tag(ContentView.ViewType.strings) };
                    if !viewModel.functionStarts.isEmpty {
                        Text(ContentView.ViewType.funcStarts.rawValue).tag(ContentView.ViewType.funcStarts) };
                    if !viewModel.selectorReferences.isEmpty {
                        Text(ContentView.ViewType.selectorRefs.rawValue).tag(ContentView.ViewType.selectorRefs) };
                    if viewModel.parsedDyldInfo != nil {
                        Text(ContentView.ViewType.dyldInfo.rawValue).tag(ContentView.ViewType.dyldInfo) };
                    if viewModel.parsedDyldInfo?.exports.isEmpty == false {
                        Text(ContentView.ViewType.exports.rawValue).tag(ContentView.ViewType.exports) } }.pickerStyle(.segmented); if selectedView == .header && viewModel.generatedHeader != nil {
                            Toggle("Show IVars", isOn: $viewModel.showIvarsInHeader).font(.caption).onChange(of: viewModel.showIvarsInHeader) { _ in
                                if let url = viewModel.parsedData?.fileURL { viewModel.processURL(url) } }.padding(.top, 2) } }.padding(.horizontal) }
            else { EmptyView() } } }
}
*/
