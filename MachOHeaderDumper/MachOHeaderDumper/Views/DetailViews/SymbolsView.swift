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
    let symbols: [Symbol] // Requires Symbol definition access
    let dynamicInfo: DynamicSymbolTableInfo? // Requires DynamicSymbolTableInfo access

    var body: some View {
        // Using the full implementation now
         List {
             // Optional: Display dynamic info ranges first
              Section("Dynamic Info") {
                  Text("Local Symbols Index: \(dynamicInfo?.localSymbolsRange?.description ?? "N/A")")
                  Text("External Defs Index: \(dynamicInfo?.externalDefinedSymbolsRange?.description ?? "N/A")")
                  Text("Undefined Symbols Index: \(dynamicInfo?.undefinedSymbolsRange?.description ?? "N/A")")
                  Text("Indirect Symbols: \(dynamicInfo?.indirectSymbolsOffset?.description ?? "N/A") (\(dynamicInfo?.indirectSymbolsCount?.description ?? "N/A"))")
              }.font(.caption)


             Section("Symbols (\(symbols.count))") {
                 ForEach(symbols.indices, id: \.self) { index in
                     let symbol = symbols[index]
                     HStack {
                         Text(symbol.name)
                             .font(.system(size: 12, design: .monospaced)).lineLimit(1)
                         Spacer()
                         Text("0x\(String(symbol.value, radix: 16))")
                             .font(.caption.monospaced()).foregroundColor(.gray)
                         Text(symbolTypeToString(symbol.type)) // Use helper defined below
                              .font(.caption).foregroundColor(symbol.isExternal ? .blue : .secondary)
                     }
                 }
             }
         }
         .listStyle(.plain)
         .textSelection(.enabled) // Allow selecting text in the list
    }

    // Helper function defined within the struct scope
    func symbolTypeToString(_ type: UInt8) -> String {
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
