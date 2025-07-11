//
//  SymbolDetailView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI
// Import MachO for N_ constants

struct SymbolDetailView: View {
    let symbol: Symbol
    var body: some View {
        List {
            Section("Symbol Details") {
                DetailRow(label: "Name", value: symbol.name, allowSelection: true)
                DetailRow(label: "Value (Address)", value: String(format: "0x%llX", symbol.value))
                DetailRow(label: "Type", value: "\(symbolTypeToString(symbol.type)) (\(symbol.type))")
                DetailRow(label: "Section", value: symbol.sectionNumber == 0 ? "NO_SECT (0)" : "\(symbol.sectionNumber)")
                DetailRow(label: "Description", value: String(format: "0x%X", symbol.description))
                DetailRow(label: "Linkage", value: symbol.isExternal ? "External" : "Internal")
            }
        }
        .navigationTitle(symbol.name)
        .navigationBarTitleDisplayMode(.inline)
        .textSelection(.enabled)
    }

    private func symbolTypeToString(_ type: UInt8) -> String {
        switch type {
        case N_UNDF: return "Undefined"
        case N_ABS: return "Absolute"
        case N_SECT: return "Defined in Section"
        case N_PBUD: return "Prebound Undefined"
        case N_INDR: return "Indirect"
        default: return "Unknown Type"
        }
    }
}

// MARK: - Helper View for Detail Rows

struct DetailRow: View {
    let label: String
    let value: String
    var allowSelection: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            if allowSelection {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                 Text(value)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview (Optional)
// struct SymbolDetailView_Previews: PreviewProvider {
//     static var previews: some View {
//         let sampleSymbol = Symbol(name: "_someVeryLongSymbolNameThatNeedsToBeDisplayedFully", type: N_SECT, sectionNumber: 1, description: 0, value: 0x1000045a0, isExternal: true)
//         NavigationView {
//              SymbolDetailView(symbol: sampleSymbol)
//         }
//     }
// }
