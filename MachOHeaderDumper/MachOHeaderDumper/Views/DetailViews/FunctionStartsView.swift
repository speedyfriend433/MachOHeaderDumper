//
//  FunctionStartsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI

struct FunctionStartsView: View {
    let starts: [FunctionStart] // Requires FunctionStart access

    var body: some View {
        List {
            Section("Function Start Addresses (\(starts.count))") {
                ForEach(starts) { start in
                    Text(String(format: "0x%llX", start.address))
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .listStyle(.plain)
        .textSelection(.enabled)
    }
}
