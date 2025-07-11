//
//  SwiftModels.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: SwiftModels.swift

import Foundation

// Basic representation of parsed Swift types
// We focus on names and kinds for now

struct SwiftTypeInfo: Identifiable {
    let id = UUID()
    let mangledName: String
    var demangledName: String? // Filled in later
    let kind: String // "Class", "Struct", "Enum", "Protocol", etc.
    let location: UInt64 // VM address where descriptor was found
    // Add fields, methods, conformances later
}

struct ExtractedSwiftMetadata {
    var types: [SwiftTypeInfo] = []
    // Add other extracted info later (e.g., functions, conformances)
}
