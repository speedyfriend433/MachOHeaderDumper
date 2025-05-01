//
//  HeaderDisplayView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/DetailViews/HeaderDisplayView.swift

import SwiftUI

struct HeaderDisplayView: View {
    let headerText: String
    var body: some View {
        GeometryReader { geometry in
            ScrollView { // Wrap TextEditor in ScrollView for reliable scrolling
                Text(headerText) // Use Text for selection, not TextEditor
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading) // Allow horizontal expansion
                    .padding(5) // Add padding inside
                    .textSelection(.enabled)
            }
            .frame(height: geometry.size.height) // Constrain ScrollView height
            .border(Color.gray.opacity(0.5), width: 1)
        }
        .padding(.horizontal, 5)
    }
}
