//
//  SymbolsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI
import MachO

struct SymbolsView: View {
    let symbols: [Symbol]
    let dynamicInfo: DynamicSymbolTableInfo?

    @State private var searchText = ""

    var filteredSymbols: [Symbol] {
        if searchText.isEmpty {
            return symbols
        } else {
            return symbols.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
         List {
            if let info = dynamicInfo {
                 Section("Dynamic Info") {
                     VStack(alignment: .leading, spacing: 4) {
                         Text("Local Symbols Index: \(info.localSymbolsRange?.description ?? "N/A")")
                         Text("External Defs Index: \(info.externalDefinedSymbolsRange?.description ?? "N/A")")
                         Text("Undefined Symbols Index: \(info.undefinedSymbolsRange?.description ?? "N/A")")
                         Text("Indirect Symbols: \(info.indirectSymbolsOffset?.description ?? "N/A") (\(info.indirectSymbolsCount?.description ?? "N/A"))")
                     }
                 }.font(.caption.monospaced())
            }

            Section("Symbols (\(filteredSymbols.count))") {
                ForEach(filteredSymbols, id: \.self) { symbol in
                    NavigationLink(destination: SymbolDetailView(symbol: symbol)) {
                        SymbolRow(symbol: symbol)
                    }
                }
            }
         }
         .listStyle(.plain)
         .searchable(text: $searchText, prompt: "Search Symbols")
    }
}

struct SymbolRow: View {
    let symbol: Symbol
    var body: some View {
        HStack {
            Text(symbol.name)
                .font(.system(size: 12, design: .monospaced)).lineLimit(1)
            Spacer()
            Text("0x\(String(symbol.value, radix: 16))")
                .font(.caption.monospaced()).foregroundColor(.gray)
            Text(symbolTypeToString(symbol.type))
                 .font(.caption).foregroundColor(symbol.isExternal ? .blue : .secondary)
        }
    }

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
