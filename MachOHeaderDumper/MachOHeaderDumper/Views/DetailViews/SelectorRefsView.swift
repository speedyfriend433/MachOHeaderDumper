//
//  SelectorRefsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/2/25.
//

import SwiftUI

struct SelectorRefsView: View {
    let refs: [SelectorReference]
    @State private var searchText = ""

    private var groupedRefs: [String: [SelectorReference]] {
        Dictionary(grouping: refs, by: { $0.selectorName })
    }

    private var sortedSelectors: [String] {
        groupedRefs.keys.sorted()
    }

    private var filteredSelectors: [String] {
        if searchText.isEmpty {
            return sortedSelectors
        } else {
            return sortedSelectors.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
            ForEach(filteredSelectors, id: \.self) { selectorName in
                Section(header: Text(selectorName).font(.system(size: 12, design: .monospaced))) {
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
