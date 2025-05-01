//
//  SwiftTypesView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/DetailViews/SwiftTypesView.swift

import SwiftUI

struct SwiftTypesView: View {
    let types: [SwiftTypeInfo] // Requires SwiftTypeInfo access

    var body: some View {
        // Use the detailed implementation
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
                .textSelection(.enabled) // Enable for whole list
            }
        }
