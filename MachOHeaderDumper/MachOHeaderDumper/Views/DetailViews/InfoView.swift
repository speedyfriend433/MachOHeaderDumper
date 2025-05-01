//
//  InfoView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/DetailViews/InfoView.swift

import SwiftUI

struct InfoView: View {
    let parsedData: ParsedMachOData // Requires ParsedMachOData definition access
    var body: some View {
        ScrollView {
            Text(parsedData.formattedHeaderInfo) // Requires formattedHeaderInfo access
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
