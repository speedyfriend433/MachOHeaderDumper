//
//  SymbolsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/DetailViews/SymbolsView.swift

import SwiftUI
import MachO // For N_ constants

struct SymbolsView: View {
    let symbols: [Symbol] // Requires Symbol struct access
    let dynamicInfo: DynamicSymbolTableInfo? // Requires DynamicSymbolTableInfo access

    var body: some View {
         List {
            // Optional: Display dynamic info ranges first
            if let info = dynamicInfo { // Use if let for safer unwrapping
                 Section("Dynamic Info") {
                     Text("Local Symbols Index: \(info.localSymbolsRange?.description ?? "N/A")")
                     Text("External Defs Index: \(info.externalDefinedSymbolsRange?.description ?? "N/A")")
                     Text("Undefined Symbols Index: \(info.undefinedSymbolsRange?.description ?? "N/A")")
                     Text("Indirect Symbols: \(info.indirectSymbolsOffset?.description ?? "N/A") (\(info.indirectSymbolsCount?.description ?? "N/A"))")
                 }.font(.caption)
            }


            Section("Symbols (\(symbols.count))") {
                // Iterate through symbols and wrap each row in a NavigationLink
                ForEach(symbols.indices, id: \.self) { index in
                    // Destination is a new detail view we'll create
                    NavigationLink(destination: SymbolDetailView(symbol: symbols[index])) {
                        // The existing row view becomes the label for the NavigationLink
                        SymbolRow(symbol: symbols[index])
                    }
                }
            }
         }
         .listStyle(.plain)
         // Text selection on the list itself might interfere with NavigationLink taps
         // Consider enabling selection only within the Detail View.
         // .textSelection(.enabled)
    }
}

// Keep SymbolRow for the list display
struct SymbolRow: View {
    let symbol: Symbol
    var body: some View {
        HStack {
            Text(symbol.name)
                .font(.system(size: 12, design: .monospaced)).lineLimit(1) // Keep line limit here
            Spacer()
            Text("0x\(String(symbol.value, radix: 16))")
                .font(.caption.monospaced()).foregroundColor(.gray)
            Text(symbolTypeToString(symbol.type))
                 .font(.caption).foregroundColor(symbol.isExternal ? .blue : .secondary)
        }
    }

    // Helper function defined within the struct scope or globally
    private func symbolTypeToString(_ type: UInt8) -> String {
        switch type {
        case N_UNDF: return "UNDF"
        case N_ABS: return "ABS"
        case N_SECT: return "SECT"
        case N_PBUD: return "PBUD"
        case N_INDR: return "INDR"
        default: return "???"
        }
    }
}
