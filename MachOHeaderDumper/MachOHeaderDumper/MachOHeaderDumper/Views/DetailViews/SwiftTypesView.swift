//
//  SwiftTypesView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI

struct SwiftTypesView: View {
    let types: [SwiftTypeInfo]

    var body: some View {
        List {
            Section("Swift Types (\(types.count))") {
                 ForEach(types) { typeInfo in
                     VStack(alignment: .leading) {
                         Text(typeInfo.demangledName ?? typeInfo.mangledName)
                             .font(.system(size: 12, design: .monospaced).bold())
                             .textSelection(.enabled)

                         HStack {
                             Text(typeInfo.kind).font(.caption).foregroundColor(.purple)
                             Spacer()
                             Text("0x\(String(typeInfo.location, radix: 16))").font(.caption.monospaced()).foregroundColor(.gray)
                         }
                         if let demangled = typeInfo.demangledName, demangled != typeInfo.mangledName {
                              Text(typeInfo.mangledName).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray).textSelection(.enabled)
                         }
                     }
                 }
            }
        }
        .listStyle(.plain)
                .textSelection(.enabled)
            }
        }
