//
//  FoundString.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Models/FoundString.swift

import Foundation

struct FoundString: Identifiable, Hashable { // Hashable for potential ForEach without indices
    let id = UUID()
    let string: String
    let address: UInt64 // VM Address where the string starts
    let fileOffset: UInt64 // File offset where the string starts
    let sectionName: String // Section it was found in (e.g., "__cstring", "__objc_classname")

    // Hashable conformance (based on content and location)
    func hash(into hasher: inout Hasher) {
        hasher.combine(string)
        hasher.combine(address)
    }

    // Equatable conformance needed for Hashable
    static func == (lhs: FoundString, rhs: FoundString) -> Bool {
        lhs.string == rhs.string && lhs.address == rhs.address
    }
}
