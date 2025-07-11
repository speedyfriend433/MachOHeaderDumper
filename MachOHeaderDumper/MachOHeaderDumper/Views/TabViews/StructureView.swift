import SwiftUI

struct StructureView: View {
    @ObservedObject var viewModel: MachOViewModel

    var body: some View {
        List {
            if let parsed = viewModel.parsedData {
                NavigationLink(destination: InfoView(parsedData: parsed).navigationTitle("Header Info")) {
                     InfoRow(title: "Header Info",
                             subtitle: "File type, architecture, UUID, etc.",
                             sfSymbol: "info.circle.fill",
                             color: .cyan)
                }
                NavigationLink(destination: LoadCommandsView(loadCommands: parsed.loadCommands).navigationTitle("Load Commands")) {
                     InfoRow(title: "Load Commands",
                             subtitle: "\(parsed.loadCommands.count) commands",
                             sfSymbol: "list.bullet.rectangle.portrait.fill",
                             color: .green)
                }
                if !viewModel.functionStarts.isEmpty {
                    NavigationLink(destination: FunctionStartsView(starts: viewModel.functionStarts).navigationTitle("Function Starts")) {
                         InfoRow(title: "Function Starts",
                                 subtitle: "\(viewModel.functionStarts.count) addresses found",
                                 sfSymbol: "play.fill",
                                 color: .purple)
                    }
                } else {
                     InfoRow(title: "Function Starts", subtitle: "LC_FUNCTION_STARTS not found.", sfSymbol: "play.slash", color: .gray)
                }
            } else {
                ContentUnavailableView(title: "No Data", description: "Import a file to see its structure.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Structure")
    }
}
