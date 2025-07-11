import SwiftUI

struct ViewSelectorView: View {
    @ObservedObject var viewModel: MachOViewModel
    @Binding var selectedView: ViewType 

    var body: some View {
        Group {
            if viewModel.parsedData != nil && !viewModel.isLoading {
                VStack(spacing: 5) {
                    Picker("View", selection: $selectedView) {
                        if let header = viewModel.generatedHeader, !header.contains("No Objective-C interfaces") {
                            Text(ViewType.objcDump.rawValue).tag(ViewType.objcDump)
                        }
                        if let swiftDump = viewModel.generatedHeader, !swiftDump.contains("//") {
                            Text(ViewType.swiftDump.rawValue).tag(ViewType.swiftDump)
                        }
                    }
                    .pickerStyle(.menu)

                    if selectedView == .objcDump && viewModel.generatedHeader != nil {
                        Toggle("Show IVars", isOn: $viewModel.showIvarsInHeader)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 5)
            } else { EmptyView() }
        }
    }
}
