//
//  CategoriesView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/2/25.
//

import SwiftUI

struct CategoriesView: View {
    let categories: [ExtractedCategory] 
    @State private var searchText = ""

    var filteredCategories: [ExtractedCategory] {
        if searchText.isEmpty {
            return categories
        } else {
            return categories.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.className.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        List {
            ForEach(filteredCategories, id: \.name) { category in
                Section(header: Text("\(category.className) (\(category.name))").font(.headline.monospaced())) {
                    if !category.instanceMethods.isEmpty {
                         Text("Instance Methods (\(category.instanceMethods.count))").font(.caption).foregroundColor(.secondary)
                         ForEach(category.instanceMethods, id: \.name) { method in
                             Text("- \(method.name)").font(.system(size: 11, design: .monospaced))
                         }
                    }
                     if !category.classMethods.isEmpty {
                          Text("Class Methods (\(category.classMethods.count))").font(.caption).foregroundColor(.secondary)
                          ForEach(category.classMethods, id: \.name) { method in
                              Text("+ \(method.name)").font(.system(size: 11, design: .monospaced))
                          }
                     }
                     if !category.instanceProperties.isEmpty {
                          Text("Instance Properties (\(category.instanceProperties.count))").font(.caption).foregroundColor(.secondary)
                          ForEach(category.instanceProperties, id: \.name) { prop in
                              Text("@prop \(prop.name)").font(.system(size: 11, design: .monospaced))
                          }
                     }
                     if !category.classProperties.isEmpty {
                          Text("Class Properties (\(category.classProperties.count))").font(.caption).foregroundColor(.secondary)
                          ForEach(category.classProperties, id: \.name) { prop in
                              Text("@prop+ \(prop.name)").font(.system(size: 11, design: .monospaced))
                          }
                     }
                     if !category.protocols.isEmpty {
                          Text("Adopted Protocols: \(category.protocols.joined(separator: ", "))")
                              .font(.caption).foregroundColor(.secondary)
                     }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search Categories or Classes")
        .textSelection(.enabled)
    }
}
