//
//  StatusEnums.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Utils/StatusEnums.swift (New File or add to existing Utils)

import Foundation
import SwiftUI

enum DemanglerStatus: CustomStringConvertible, Equatable {
    case idle
    case notAttempted // e.g., Swift sections not found
    case lookupFailed // dlopen/dlsym failed
    case notFound     // Lookup succeeded, but symbol wasn't present
    case found        // Successfully found function pointer

    var description: String {
        switch self {
        case .idle: return "" // Don't show anything initially
        case .notAttempted: return "Demangler: N/A"
        case .lookupFailed: return "Demangler Lookup Failed"
        case .notFound: return "Demangler Not Found"
        case .found: return "Demangler Found"
        }
    }

    var color: Color { // Optional: For UI styling
        switch self {
        case .idle, .notAttempted: return .gray
        case .lookupFailed, .notFound: return .orange
        case .found: return .green
        }
    }
}
