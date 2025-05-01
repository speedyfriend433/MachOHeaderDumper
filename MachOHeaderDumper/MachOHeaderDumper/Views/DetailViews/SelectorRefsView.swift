//
//  SelectorRefsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/2/25.
//

import SwiftUI

struct SelectorRefsView: View {
    let refs: [SelectorReference] // Requires SelectorReference access
    @State private var searchText = ""

    // Group references by selector name for better display
    private var groupedRefs: [String: [SelectorReference]] {
        Dictionary(grouping: refs, by: { $0.selectorName })
    }

    // Sort selectors alphabetically
    private var sortedSelectors: [String] {
        groupedRefs.keys.sorted()
    }

    // Filtered selectors based on search
    private var filteredSelectors: [String] {
        if searchText.isEmpty {
            return sortedSelectors
        } else {
            return sortedSelectors.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
            // Iterate through sorted+filtered selector names
            ForEach(filteredSelectors, id: \.self) { selectorName in
                Section(header: Text(selectorName).font(.system(size: 12, design: .monospaced))) {
                    // List the addresses where this selector is referenced
                    if let references = groupedRefs[selectorName] {
                         ForEach(references) { ref in
                             Text(String(format: "0x%llX", ref.referenceAddress))
                                 .font(.system(.caption, design: .monospaced))
                                 .foregroundColor(.gray)
                         }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search Selectors")
        .textSelection(.enabled)
    }
}
