//
//  MainContentView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/SupportingViews/MainContentView.swift

import SwiftUI

struct MainContentView: View {
    @ObservedObject var viewModel: MachOViewModel
    let selectedView: ContentView.ViewType
    var body: some View { Group { if viewModel.isLoading { Spacer(); ProgressView("Processing..."); Spacer() } else if let parsed = viewModel.parsedData { switch selectedView { case .header: if let headerText = viewModel.generatedHeader { HeaderDisplayView(headerText: headerText) } else { ContentUnavailableView(title: "ObjC Header Not Available", description: "No Objective-C classes or protocols were found.") } case .info: InfoView(parsedData: parsed); case .loadCmds: LoadCommandsView(loadCommands: parsed.loadCommands); case .symbols: if let symbols = parsed.symbols, !symbols.isEmpty { SymbolsView(symbols: symbols, dynamicInfo: parsed.dynamicSymbolInfo) } else { ContentUnavailableView(title: "No Symbols Found", description: "The symbol table might be missing or stripped.") } case .dyldInfo: if let dyldInfo = viewModel.parsedDyldInfo { DyldInfoView(info: dyldInfo) } else { ContentUnavailableView(title: "Dyld Info Not Available", description: "LC_DYLD_INFO(_ONLY) command might be missing.") } case .swiftTypes: if !viewModel.extractedSwiftTypes.isEmpty { SwiftTypesView(types: viewModel.extractedSwiftTypes) } else { ContentUnavailableView(title: "No Swift Types Found", description: "__swift5_types section might be missing.") } case .exports: if let exports = viewModel.parsedDyldInfo?.exports, !exports.isEmpty { ExportsView(exports: exports, imageBase: parsed.baseAddress) } else { ContentUnavailableView(title: "No Exports Found", description: "The export trie might be missing or empty.") } case .strings:
        if !viewModel.foundStrings.isEmpty {
                                 StringsView(strings: viewModel.foundStrings)
        } else { ContentUnavailableView(title: "No Strings Found", description: "Relevant sections might be empty or strings too short.") }
    } } else { if viewModel.errorMessage == nil { ContentUnavailableView(title: "No File Loaded", description: "Tap the button above to import a Mach-O file.", systemImage: "doc.badge.plus") } else { ContentUnavailableView(title: "Parsing Failed", description: viewModel.errorMessage ?? "An unknown error occurred.", systemImage: "xmark.octagon.fill").foregroundColor(.red) } } }.frame(maxWidth: .infinity, maxHeight: .infinity) }
}
