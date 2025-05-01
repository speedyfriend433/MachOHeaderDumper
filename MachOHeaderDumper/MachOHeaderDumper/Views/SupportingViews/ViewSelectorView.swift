//
//  ViewSelectorView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/SupportingViews/ViewSelectorView.swift (Corrected Braces & Modifiers)

import SwiftUI

struct ViewSelectorView: View {
    @ObservedObject var viewModel: MachOViewModel
    @Binding var selectedView: ContentView.ViewType
    var body: some View { Group { if let parsedData = viewModel.parsedData, !viewModel.isLoading { VStack(spacing: 5) { Picker("View", selection: $selectedView) { if viewModel.generatedHeader != nil { Text(ContentView.ViewType.header.rawValue).tag(ContentView.ViewType.header) }; if !viewModel.extractedSwiftTypes.isEmpty { Text(ContentView.ViewType.swiftTypes.rawValue).tag(ContentView.ViewType.swiftTypes) }; Text(ContentView.ViewType.info.rawValue).tag(ContentView.ViewType.info); Text(ContentView.ViewType.loadCmds.rawValue).tag(ContentView.ViewType.loadCmds); if parsedData.symbols?.isEmpty == false { Text(ContentView.ViewType.symbols.rawValue).tag(ContentView.ViewType.symbols) }; if viewModel.parsedDyldInfo != nil { Text(ContentView.ViewType.dyldInfo.rawValue).tag(ContentView.ViewType.dyldInfo) }; if viewModel.parsedDyldInfo?.exports.isEmpty == false { Text(ContentView.ViewType.exports.rawValue).tag(ContentView.ViewType.exports) } }.pickerStyle(.segmented); if selectedView == .header && viewModel.generatedHeader != nil { Toggle("Show IVars", isOn: $viewModel.showIvarsInHeader).font(.caption).onChange(of: viewModel.showIvarsInHeader) { _ in if let url = viewModel.parsedData?.fileURL { viewModel.processURL(url) } }.padding(.top, 2) } }.padding(.horizontal) } else { EmptyView() } } }
}
