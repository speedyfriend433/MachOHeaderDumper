////
////  StatusEnums.swift
////  MachOHeaderDumper
////
////  Created by 이지안 on 5/1/25.
////
//
//
//import Foundation
//import SwiftUI
//
//enum DemanglerStatus: CustomStringConvertible, Equatable {
//    case idle
//    case notAttempted
//    case lookupFailed
//    case notFound
//    case found
//
//    var description: String {
//        switch self {
//        case .idle: return ""
//        case .notAttempted: return "Demangler: N/A"
//        case .lookupFailed: return "Demangler Lookup Failed"
//        case .notFound: return "Demangler Not Found"
//        case .found: return "Demangler Found"
//        }
//    }
//
//    var color: Color {
//        switch self {
//        case .idle, .notAttempted: return .gray
//        case .lookupFailed, .notFound: return .orange
//        case .found: return .green
//        }
//    }
//}
