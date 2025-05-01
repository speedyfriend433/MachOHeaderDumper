//
//  SymbolDetailView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/DetailViews/SymbolDetailView.swift

import SwiftUI
// Import MachO if N_ constants are needed directly, otherwise use descriptions
// import MachO

struct SymbolDetailView: View {
    let symbol: Symbol // Requires Symbol struct access

    var body: some View {
        // Use a List or Form for structured presentation
        List {
            Section("Symbol Details") {
                DetailRow(label: "Name", value: symbol.name, allowSelection: true) // Allow selecting name
                DetailRow(label: "Value (Address)", value: String(format: "0x%llX", symbol.value))
                DetailRow(label: "Type", value: "\(symbolTypeToString(symbol.type)) (\(symbol.type))")
                DetailRow(label: "Section", value: symbol.sectionNumber == 0 ? "NO_SECT (0)" : "\(symbol.sectionNumber)") // N_SECT == 0 is NO_SECT
                DetailRow(label: "Description", value: String(format: "0x%X", symbol.description)) // Usually flags/stab info
                DetailRow(label: "Linkage", value: symbol.isExternal ? "External" : "Internal")
            }
        }
        .navigationTitle(symbol.name) // Use symbol name as title (might be truncated)
        .navigationBarTitleDisplayMode(.inline)
        // Enable text selection for the whole list content
        .textSelection(.enabled)
    }

    // Helper function to convert symbol type code to string
    // (Can be defined here, globally, or passed in if needed)
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
    var allowSelection: Bool = false // Default to no selection for labels/values

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            if allowSelection {
                Text(value)
                    .font(.system(.body, design: .monospaced)) // Use monospaced for names/addresses
                    .textSelection(.enabled) // Enable only if needed
            } else {
                 Text(value)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(.vertical, 2) // Add slight vertical padding
    }
}

// MARK: - Preview (Optional)
// You might need to create a mock Symbol object for the preview
// struct SymbolDetailView_Previews: PreviewProvider {
//     static var previews: some View {
//         // Create a sample Symbol conforming to the struct definition
//         let sampleSymbol = Symbol(name: "_someVeryLongSymbolNameThatNeedsToBeDisplayedFully", type: N_SECT, sectionNumber: 1, description: 0, value: 0x1000045a0, isExternal: true)
//         NavigationView { // Wrap in NavigationView for title display
//              SymbolDetailView(symbol: sampleSymbol)
//         }
//     }
// }
