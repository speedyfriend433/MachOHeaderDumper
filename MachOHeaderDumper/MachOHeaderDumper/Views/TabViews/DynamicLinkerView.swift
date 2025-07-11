import SwiftUI

struct DynamicLinkerView: View {
    @ObservedObject var viewModel: MachOViewModel

    var body: some View {
        List {
            if !viewModel.extractedCategories.isEmpty {
                 NavigationLink(destination: CategoriesView(categories: viewModel.extractedCategories).navigationTitle("Categories")) {
                      InfoRow(title: "Objective-C Categories",
                              subtitle: "\(viewModel.extractedCategories.count) found",
                              sfSymbol: "puzzlepiece.extension.fill",
                              color: .pink)
                 }
            }
            if !viewModel.selectorReferences.isEmpty {
                 NavigationLink(destination: SelectorRefsView(refs: viewModel.selectorReferences).navigationTitle("Selector References")) {
                      InfoRow(title: "Selector References",
                              subtitle: "\(viewModel.selectorReferences.count) found",
                              sfSymbol: "at",
                              color: .teal)
                 }
            }

            if let dyldInfo = viewModel.parsedDyldInfo {
                NavigationLink(destination: DyldInfoView(info: dyldInfo).navigationTitle("Dyld Bindings")) {
                     InfoRow(title: "Dyld Bind/Rebase",
                             subtitle: "\(dyldInfo.binds.count + dyldInfo.rebases.count) operations",
                             sfSymbol: "arrow.left.arrow.right.circle.fill",
                             color: .indigo)
                }
                if !dyldInfo.exports.isEmpty {
                     NavigationLink(destination: ExportsView(exports: dyldInfo.exports, imageBase: viewModel.parsedData?.baseAddress ?? 0).navigationTitle("Exports")) {
                          InfoRow(title: "Exports",
                                  subtitle: "\(dyldInfo.exports.count) symbols exported",
                                  sfSymbol: "arrow.up.right.circle.fill",
                                  color: .brown)
                     }
                }
            } else {
                 InfoRow(title: "Dyld Information", subtitle: "LC_DYLD_INFO not found.", sfSymbol: "link.slash", color: .gray)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dynamic Linker")
    }
}
