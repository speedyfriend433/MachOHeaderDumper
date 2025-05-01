//
//  ContentUnavailableView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/SupportingViews/ContentUnavailableView.swift

import SwiftUI

// MARK: - Placeholder View (Definition needed)
struct ContentUnavailableView: View {
    let title: String; var description: String? = nil; var systemImage: String? = "doc.text.magnifyingglass"
    var body: some View { VStack(spacing: 15) { Spacer(); if let systemImage = systemImage { Image(systemName: systemImage).font(.system(size: 50)).foregroundColor(.secondary) }; Text(title).font(.title3).fontWeight(.bold); if let description = description { Text(description).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal) }; Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity).textSelection(.enabled) }
}

