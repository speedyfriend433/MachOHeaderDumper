import SwiftUI

struct MainContentView: View {
    @ObservedObject var viewModel: MachOViewModel
    let selectedView: ViewType

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Processing...")
                        .progressViewStyle(.circular)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
            } else if let parsed = viewModel.parsedData {
                determineContentView(selectedView: selectedView, parsedData: parsed)
            } else {
                if viewModel.errorMessage == nil {
                    ContentUnavailableView(
                         title: "No File Loaded",
                         description: "Tap the button above to import a Mach-O file.",
                         systemImage: "doc.badge.plus"
                    )
                } else {
                     ContentUnavailableView(
                          title: "Parsing Failed",
                          description: viewModel.errorMessage ?? "An unknown error occurred.",
                          systemImage: "xmark.octagon.fill"
                     ).foregroundColor(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper to Determine Content View

    @ViewBuilder
    private func determineContentView(selectedView: ViewType, parsedData: ParsedMachOData) -> some View {
        switch selectedView {
        case .objcDump:
            if let headerText = viewModel.generatedHeader, !headerText.contains("No Objective-C interfaces") {
                HeaderDisplayView(headerText: headerText)
            } else {
                ContentUnavailableView(title: "No Objective-C Interfaces", description: "No new classes, protocols, or categories were found.")
            }

        case .swiftDump:
             if let swiftText = viewModel.generatedHeader, !swiftText.starts(with: "//") {
                 HeaderDisplayView(headerText: swiftText)
             } else {
                 ContentUnavailableView(title: "Swift Dump Not Available", description: "No Swift info found or dump failed.")
             }

        case .info:
            InfoView(parsedData: parsedData)

        case .categories:
             if !viewModel.extractedCategories.isEmpty {
                 CategoriesView(categories: viewModel.extractedCategories)
             } else {
                 ContentUnavailableView(title: "No Categories Found")
             }

        case .loadCmds:
            LoadCommandsView(loadCommands: parsedData.loadCommands)

        case .strings:
             if !viewModel.foundStrings.isEmpty {
                 StringsView(strings: viewModel.foundStrings)
             } else {
                 ContentUnavailableView(title: "No Strings Found")
             }

        case .funcStarts:
             if !viewModel.functionStarts.isEmpty {
                 FunctionStartsView(starts: viewModel.functionStarts)
             } else {
                 ContentUnavailableView(title: "No Function Starts Found")
             }

        case .symbols:
            if let syms = parsedData.symbols, !syms.isEmpty {
                SymbolsView(symbols: syms, dynamicInfo: parsedData.dynamicSymbolInfo)
            } else {
                ContentUnavailableView(title: "No Symbols Found")
            }

        case .dyldInfo:
            if let dyld = viewModel.parsedDyldInfo {
                DyldInfoView(info: dyld)
            } else {
                ContentUnavailableView(title: "Dyld Info Not Available")
            }

        case .exports:
            if let exports = viewModel.parsedDyldInfo?.exports, !exports.isEmpty {
                ExportsView(exports: exports, imageBase: parsedData.baseAddress)
            } else {
                ContentUnavailableView(title: "Exports Not Available")
            }

        case .selectorRefs:
             if !viewModel.selectorReferences.isEmpty {
                 SelectorRefsView(refs: viewModel.selectorReferences)
             } else {
                 ContentUnavailableView(title: "No Selector References Found")
             }
        }
    }
}
