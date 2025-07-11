//
//  HeaderDisplayView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI

struct HeaderDisplayView: View {
    let headerText: String
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Text(headerText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                    .textSelection(.enabled)
            }
            .frame(height: geometry.size.height)
            .border(Color.gray.opacity(0.5), width: 1)
        }
        .padding(.horizontal, 5)
    }
}
