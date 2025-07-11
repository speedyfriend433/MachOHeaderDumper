//
//  LoadCommandsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI
import MachO // VM_PROT constants

struct LoadCommandsView: View {
    let loadCommands: [ParsedLoadCommand]
    var body: some View {
        List {
            ForEach(loadCommands.indices, id: \.self) { index in
                 LoadCommandRow(command: loadCommands[index])
            }
        }
        .listStyle(.plain)
    }
}

struct LoadCommandRow: View {
    let command: ParsedLoadCommand
    var body: some View {
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
                        Text("Time: \(dylib.timestamp), CurrentVer: \(formatVersionPacked32(dylib.current_version))")
                        Text("CompatVer: \(formatVersionPacked32(dylib.compatibility_version))")
                    }
                case .loadDylinker: EmptyView()
                case .sourceVersion: EmptyView()
                case .versionMin(let cmd, let platform):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Platform: \(platform)")
                        Text("Min Version: \(formatVersionPacked32(cmd.version))")
                        Text("Min SDK: \(formatVersionPacked32(cmd.sdk))")
                    }
                case .buildVersion(let cmd):
                    Text("SDK: \(formatVersionPacked32(cmd.sdk)), Tools: \(cmd.ntools)")
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

 
