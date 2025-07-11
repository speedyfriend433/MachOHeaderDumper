//
//  ExportsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI
import MachO // EXPORT constants

struct ExportsView: View {
    let exports: [ExportedSymbol]
    let imageBase: UInt64

    var body: some View {
        List {
            Section("Exports (\(exports.count))") {
                 ForEach(exports) { export in
                     VStack(alignment: .leading) {
                          Text(export.name).bold()
                          if export.isReExport {
                              Text("  -> ReExport: Lib #\(export.importLibraryOrdinal ?? 0) (\(export.importName ?? export.name))")
                                  .foregroundColor(.purple)
                          } else {
                              Text("  Addr: 0x\(String(imageBase + export.address, radix: 16)) (\(export.kind))")
                                   .foregroundColor(.blue)
                          }
                          Text("  Flags: 0x\(String(export.flags, radix: 16)) \(self.formatExportFlags(export.flags))")
                                .foregroundColor(.gray)
                          if let other = export.otherOffset, export.hasStubAndResolver {
                               Text("  Resolver Offset: 0x\(String(other, radix: 16))")
                                   .foregroundColor(.gray)
                           }
                     }
                     .font(.system(size: 11, design: .monospaced))
                 }
            }
        }
        .listStyle(.plain)
        .textSelection(.enabled)
    }

    func formatExportFlags(_ flags: UInt64) -> String {
        var parts: [String] = []
        if (flags & EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION) != 0 { parts.append("WeakDef") }
        if (flags & EXPORT_SYMBOL_FLAGS_REEXPORT) != 0 { parts.append("ReExport") }
        if (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER) != 0 { parts.append("StubAndResolver") }
        return parts.isEmpty ? "" : "[\(parts.joined(separator: ", "))]"
    }
}
