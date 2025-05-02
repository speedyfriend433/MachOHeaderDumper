//
//  MainContentView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/SupportingViews/MainContentView.swift (Complete Code)

import SwiftUI

// Assume ContentView.ViewType enum and necessary Model/View structs are accessible
// Either via import or by being in the same target.

struct MainContentView: View {
    // Use ObservedObject as this view observes but doesn't own the ViewModel
    @ObservedObject var viewModel: MachOViewModel
    // Pass the currently selected view type state
    let selectedView: ContentView.ViewType

    var body: some View {
        // Use Group to ensure a single root View is returned from the body
        Group {
            if viewModel.isLoading {
                // --- Loading State ---
                VStack { // Center the ProgressView
                    Spacer()
                    ProgressView("Processing...")
                        .progressViewStyle(.circular)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
            } else if let parsed = viewModel.parsedData {
                // --- Content Display based on Selection ---
                // The helper function determines WHICH view to show
                // Using @ViewBuilder allows returning different View types
                determineContentView(
                    selectedView: selectedView,
                    parsedData: parsed,
                    viewModel: viewModel // Pass view model for easy access to @Published properties
                )
            } else {
                // --- Idle or Fatal Error State ---
                // Display appropriate placeholder based on whether an error occurred
                if viewModel.errorMessage == nil { // Idle state
                    ContentUnavailableView(
                         title: "No File Loaded",
                         description: "Tap the button above to import a Mach-O file.",
                         systemImage: "doc.badge.plus"
                    )
                } else { // Fatal Error during parsing state
                     ContentUnavailableView(
                          title: "Parsing Failed",
                          description: viewModel.errorMessage ?? "An unknown error occurred.",
                          systemImage: "xmark.octagon.fill"
                     ).foregroundColor(.red) // Indicate error
                }
            }
        }
        // Apply frame modifier to the Group to allow content to expand
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper to Determine Content View

    /// This private helper function contains the switch statement to decide which detail view to show.
    /// Using @ViewBuilder allows returning different View types from each case.
    @ViewBuilder
        private func determineContentView(
            selectedView: ContentView.ViewType,
            parsedData: ParsedMachOData,
            viewModel: MachOViewModel
        ) -> some View {
            // FIX: Ensure ALL cases from ContentView.ViewType are present
            switch selectedView {
            case .objcDump:
                if let headerText = viewModel.objcHeaderOutput, !headerText.starts(with: "// Dump failed") {
                    HeaderDisplayView(headerText: headerText)
                } else { ContentUnavailableView(title: "ObjC Dump Not Available") }

            case .swiftDump:
                 if let swiftText = viewModel.swiftDumpOutput, !swiftText.starts(with: "// Dump failed") {
                     HeaderDisplayView(headerText: swiftText)
                 } else { ContentUnavailableView(title: "Swift Dump Not Available") }

            case .info:
                InfoView(parsedData: parsedData)

            case .categories: // Handles categories
                 if !viewModel.extractedCategories.isEmpty {
                     CategoriesView(categories: viewModel.extractedCategories)
                 } else { ContentUnavailableView(title: "No Categories Found") }

            case .loadCmds:
                LoadCommandsView(loadCommands: parsedData.loadCommands)

            case .strings: // Handles strings
                 if !viewModel.foundStrings.isEmpty {
                     StringsView(strings: viewModel.foundStrings)
                 } else { ContentUnavailableView(title: "No Strings Found") }

            case .funcStarts: // Handles funcStarts
                 if !viewModel.functionStarts.isEmpty {
                     FunctionStartsView(starts: viewModel.functionStarts)
                 } else { ContentUnavailableView(title: "No Function Starts Found") }

            case .symbols:
                if let syms = parsedData.symbols, !syms.isEmpty {
                    SymbolsView(symbols: syms, dynamicInfo: parsedData.dynamicSymbolInfo)
                } else { ContentUnavailableView(title: "No Symbols Found") }

            case .dyldInfo:
                if let dyld = viewModel.parsedDyldInfo {
                    DyldInfoView(info: dyld)
                } else { ContentUnavailableView(title: "Dyld Info Not Available") }

            case .exports:
                if let exports = viewModel.parsedDyldInfo?.exports, !exports.isEmpty {
                    ExportsView(exports: exports, imageBase: parsedData.baseAddress)
                } else { ContentUnavailableView(title: "Exports Not Available") }

            case .selectorRefs: // Handles selectorRefs
                 if !viewModel.selectorReferences.isEmpty {
                     SelectorRefsView(refs: viewModel.selectorReferences)
                 } else { ContentUnavailableView(title: "No Selector References Found") }

            // No 'default' needed if all cases are explicitly handled.
            // If the error persists, double-check the ViewType enum definition
            // in ContentView.swift for any extra/missing cases compared to this switch.
            } // End Switch
        } // End determineContentView
    } // End MainContentView

// Ensure that all referenced View structs (HeaderDisplayView, InfoView, LoadCommandsView, SymbolsView, DyldInfoView, ExportsView, StringsView, FunctionStartsView, ContentUnavailableView) and Model structs (ParsedMachOData, Symbol, DynamicSymbolTableInfo, ParsedDyldInfo, SwiftTypeInfo, FoundString, FunctionStart) as well as ContentView.ViewType enum are defined and accessible in the project scope.
