//
//  StringsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

import SwiftUI

struct StringsView: View {
    let strings: [FoundString] // Requires FoundString access
    @State private var searchText = ""

    var filteredStrings: [FoundString] {
        if searchText.isEmpty {
            return strings
        } else {
            // Case-insensitive search
            return strings.filter { $0.string.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
            Section("Found Strings (\(filteredStrings.count))") {
                ForEach(filteredStrings) { foundStr in
                    VStack(alignment: .leading) {
                        Text(foundStr.string)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(3) // Show a few lines initially
                        HStack {
                             Text(foundStr.sectionName)
                                 .font(.caption2)
                                 .foregroundColor(.purple)
                             Spacer()
                             Text("0x\(String(foundStr.address, radix: 16))")
                                 .font(.caption2.monospaced())
                                 .foregroundColor(.gray)
                         }
                    }
                     .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search Strings") // Add search bar
        .textSelection(.enabled) // Enable selection
    }
}
