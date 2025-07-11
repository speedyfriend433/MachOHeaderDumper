//
//  InfoView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI

struct InfoView: View {
    let parsedData: ParsedMachOData
    var body: some View {
        ScrollView {
            Text(parsedData.formattedHeaderInfo)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
