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
    @Binding var selectedView: ContentView.ViewType // Use updated enum

    var body: some View {
        Group {
            if viewModel.parsedData != nil && !viewModel.isLoading {
                VStack(spacing: 5) {
                    Picker("View", selection: $selectedView) {
                        // Check viewmodel output properties
                        if viewModel.objcHeaderOutput != nil { Text(ContentView.ViewType.objcDump.rawValue).tag(ContentView.ViewType.objcDump) }
                        if viewModel.swiftDumpOutput != nil { Text(ContentView.ViewType.swiftDump.rawValue).tag(ContentView.ViewType.swiftDump) }
                        Text(ContentView.ViewType.info.rawValue).tag(ContentView.ViewType.info)
                        Text(ContentView.ViewType.loadCmds.rawValue).tag(ContentView.ViewType.loadCmds)
                        if viewModel.parsedData?.symbols?.isEmpty == false { Text(ContentView.ViewType.symbols.rawValue).tag(ContentView.ViewType.symbols) }
                        if viewModel.parsedDyldInfo != nil { Text(ContentView.ViewType.dyldInfo.rawValue).tag(ContentView.ViewType.dyldInfo) }
                        if viewModel.parsedDyldInfo?.exports.isEmpty == false { Text(ContentView.ViewType.exports.rawValue).tag(ContentView.ViewType.exports) }
                        if !viewModel.foundStrings.isEmpty { Text(ContentView.ViewType.strings.rawValue).tag(ContentView.ViewType.strings) }
                        if !viewModel.functionStarts.isEmpty { Text(ContentView.ViewType.funcStarts.rawValue).tag(ContentView.ViewType.funcStarts) }
                    }
                    .pickerStyle(.menu) // KEEP MENU STYLE

                    // Toggle might not apply directly to ObjC Dump anymore, or library might have options
                    // if selectedView == .objcDump && viewModel.objcHeaderOutput != nil { ... Toggle ... }
                }
                .padding(.horizontal)
            } else { EmptyView() }
        }
    }
}
