//
//  DyldInfoView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI

struct DyldInfoView: View {
    let info: ParsedDyldInfo

    var body: some View {
         List {
             Section("Rebase Operations (\(info.rebases.count))") {
                 ForEach(info.rebases) { rebase in
                     HStack {
                         Text("Seg \(rebase.segmentIndex) + 0x\(String(rebase.segmentOffset, radix: 16))")
                         Spacer()
                         Text(rebase.typeDescription)
                     }.font(.system(size: 11, design: .monospaced))
                 }
             }
             Section("Bind Operations (\(info.binds.count))") {
                 ForEach(info.binds) { bind in
                     VStack(alignment: .leading) {
                         HStack { Text("Seg \(bind.segmentIndex) + 0x\(String(bind.segmentOffset, radix: 16))"); Spacer(); Text(bind.typeDescription); if bind.isWeakImport { Text("WEAK").foregroundColor(.orange) } }
                         Text("  -> \(bind.symbolName) (\(bind.ordinalDescription)) Addend: \(bind.addend)").foregroundColor(.gray)
                     }.font(.system(size: 11, design: .monospaced))
                 }
             }
             Section("Weak Bind Operations (\(info.weakBinds.count))") {
                 ForEach(info.weakBinds) { bind in
                     VStack(alignment: .leading) {
                         HStack { Text("Seg \(bind.segmentIndex) + 0x\(String(bind.segmentOffset, radix: 16))"); Spacer(); Text(bind.typeDescription); if bind.isWeakImport { Text("WEAK").foregroundColor(.orange) } }
                         Text("  -> \(bind.symbolName) (\(bind.ordinalDescription)) Addend: \(bind.addend)").foregroundColor(.gray)
                     }.font(.system(size: 11, design: .monospaced))
                 }
             }
              Section("Lazy Bind Operations (\(info.lazyBinds.count))") {
                 ForEach(info.lazyBinds) { bind in
                     VStack(alignment: .leading) {
                         HStack { Text("Seg \(bind.segmentIndex) + 0x\(String(bind.segmentOffset, radix: 16))"); Spacer(); Text(bind.typeDescription); if bind.isWeakImport { Text("WEAK").foregroundColor(.orange) } }
                         Text("  -> \(bind.symbolName) (\(bind.ordinalDescription)) Addend: \(bind.addend)").foregroundColor(.gray)
                     }.font(.system(size: 11, design: .monospaced))
                 }
             }
         }
         .listStyle(.plain)
         .textSelection(.enabled)
    }
}
