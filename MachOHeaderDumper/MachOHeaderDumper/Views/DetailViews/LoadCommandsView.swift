//
//  LoadCommandsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/DetailViews/LoadCommandsView.swift

import SwiftUI
import MachO // For VM_PROT constants if vmProtToString is here

struct LoadCommandsView: View {
    let loadCommands: [ParsedLoadCommand] // Requires ParsedLoadCommand definition access
    var body: some View {
        // Using the SIMPLIFIED version for now to avoid type-checking errors
        List {
            ForEach(loadCommands.indices, id: \.self) { index in
                 // Consider making LoadCommandRow identifiable if possible
                 LoadCommandRow(command: loadCommands[index]) // Use the sub-view
            }
        }
        .listStyle(.plain)
    }
}

// Keep LoadCommandRow struct definition here
struct LoadCommandRow: View {
    let command: ParsedLoadCommand // Requires ParsedLoadCommand definition access
    var body: some View {
        // Use the more detailed implementation now that files are separate
        VStack(alignment: .leading, spacing: 3) {
            Text(command.description).font(.system(size: 12, design: .monospaced).bold())
            Group {
                switch command {
                case .segment64(let cmd, _):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VM Addr: 0x\(String(cmd.vmaddr, radix: 16)), Size: \(cmd.vmsize)")
                        Text("File Off: \(cmd.fileoff), Size: \(cmd.filesize)")
                        Text("Prot: \(vmProtToString(cmd.initprot))/\(vmProtToString(cmd.maxprot)), Flags: 0x\(String(cmd.flags, radix: 16))")
                    }
                case .uuid: EmptyView()
                case .symtab(let cmd):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Symbols Off: \(cmd.symoff), Num: \(cmd.nsyms)")
                        Text("Strings Off: \(cmd.stroff), Size: \(cmd.strsize)")
                    }
                case .dysymtab(let cmd):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Locals: \(cmd.ilocalsym)...\(cmd.ilocalsym + cmd.nlocalsym), ExtDefs: \(cmd.iextdefsym)...\(cmd.iextdefsym + cmd.nextdefsym)")
                        Text("Undefs: \(cmd.iundefsym)...\(cmd.iundefsym + cmd.nundefsym), Indirect: \(cmd.indirectsymoff)...\(cmd.indirectsymoff + cmd.nindirectsyms)")
                    }
                case .encryptionInfo64(let cmd):
                    Text("Crypt Off: \(cmd.cryptoff), Size: \(cmd.cryptsize)")
                case .loadDylib(_, let dylib), .idDylib(_, let dylib):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time: \(dylib.timestamp), CurrentVer: \(formatVersionPacked32(dylib.current_version))") // Requires helper access
                        Text("CompatVer: \(formatVersionPacked32(dylib.compatibility_version))") // Requires helper access
                    }
                case .loadDylinker: EmptyView()
                case .sourceVersion: EmptyView() // Description has info
                case .versionMin(let cmd, let platform):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Platform: \(platform)")
                        Text("Min Version: \(formatVersionPacked32(cmd.version))") // Requires helper access
                        Text("Min SDK: \(formatVersionPacked32(cmd.sdk))") // Requires helper access
                    }
                case .buildVersion(let cmd):
                    Text("SDK: \(formatVersionPacked32(cmd.sdk)), Tools: \(cmd.ntools)") // Requires helper access
                case .main: EmptyView()
                case .functionStarts(let cmd), .dataInCode(let cmd), .codeSignature(let cmd):
                    Text("Data Offset: \(cmd.dataoff), Size: \(cmd.datasize)")
                case .dyldInfo(let cmd):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rebase: \(cmd.rebase_off) (\(cmd.rebase_size)), Bind: \(cmd.bind_off) (\(cmd.bind_size))")
                        Text("WeakBind: \(cmd.weak_bind_off) (\(cmd.weak_bind_size))")
                        Text("LazyBind: \(cmd.lazy_bind_off) (\(cmd.lazy_bind_size)), Export: \(cmd.export_off) (\(cmd.export_size))")
                    }
                case .unknown(_, let cmdsize): Text("Cmd Size: \(cmdsize)")
                }
            }.font(.system(size: 10, design: .monospaced)).foregroundColor(.gray).padding(.leading, 10)
        }.padding(.vertical, 2).textSelection(.enabled)
    }
}

// Ensure access to formatVersionPacked32 helper (defined globally or in Utils)
