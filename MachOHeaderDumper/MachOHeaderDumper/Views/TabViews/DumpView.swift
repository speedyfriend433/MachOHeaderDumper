import SwiftUI

struct DumpView: View {
    @ObservedObject var viewModel: MachOViewModel

    var body: some View {
        List {
            // MARK: - Objective-C Dump Section
            Group {
                if let header = viewModel.generatedHeader, !header.starts(with: "//") {
                    NavigationLink(destination: HeaderDisplayView(headerText: header).navigationTitle("Objective-C Header")) {
                        InfoRow(
                            title: "Objective-C Header",
                            subtitle: "Classes, Protocols, Categories",
                            sfSymbol: "h.square.fill",
                            color: .red
                        )
                    }
                } else {
                    InfoRow(
                        title: "Objective-C Header",
                        subtitle: "No interfaces found or dump failed",
                        sfSymbol: "h.square.fill",
                        color: .gray
                    )
                }
            }

            // MARK: - Swift Dump Section
            Group {
                if let swiftDump = viewModel.generatedHeader, !swiftDump.starts(with: "//") {
                    NavigationLink(destination: HeaderDisplayView(headerText: swiftDump).navigationTitle("Swift Dump")) {
                        InfoRow(
                            title: "Swift Dump",
                            subtitle: "\(viewModel.extractedSwiftTypes.count) types found",
                            sfSymbol: "s.square.fill",
                            color: .orange
                        )
                    }
                } else {
                    InfoRow(
                        title: "Swift Dump",
                        subtitle: "No types found or dump failed",
                        sfSymbol: "s.square.fill",
                        color: .gray
                    )
                }
            }

            // MARK: - Strings Section
            Group {
                 if !viewModel.foundStrings.isEmpty {
                     NavigationLink(destination: StringsView(strings: viewModel.foundStrings).navigationTitle("Strings")) {
                          InfoRow(
                            title: "Strings",
                            subtitle: "\(viewModel.foundStrings.count) found",
                            sfSymbol: "text.quote",
                            color: .blue
                          )
                     }
                 } else {
                      InfoRow(
                        title: "Strings",
                        subtitle: "No strings found",
                        sfSymbol: "text.quote",
                        color: .gray
                      )
                 }
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dump")
    }
}

// MARK: - Supporting Views (InfoRow)

struct InfoRow: View {
    let title: String
    let subtitle: String
    let sfSymbol: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: sfSymbol)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(color.gradient)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.bold)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}
