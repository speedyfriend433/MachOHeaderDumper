//
//  MachOError.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation
import MachO // Or rely on manual definitions in MachOStructures.swift

// MARK: - Error Types

// FIX: Add Equatable conformance
enum MachOParseError: Error, LocalizedError, Equatable {
    case fileNotFound(path: String)
    case failedToOpenFile(path: String, error: Error) // Error type itself isn't Equatable
    case failedToGetFileSize(path: String)
    case mmapFailed(error: String)
    case invalidMagicNumber(magic: UInt32)
    case unsupportedArchitecture(cpuType: cpu_type_t)
    case architectureNotFound(cpuType: cpu_type_t)
    case fatHeaderReadError
    case fatArchReadError
    case thinHeaderReadError
    case loadCommandReadError
    case segmentCommandReadError
    case sectionReadError
    case dataReadOutOfBounds(offset: Int, length: Int, totalSize: Int)
    case addressResolutionFailed(vmaddr: UInt64)
    case sectionNotFound(segment: String, section: String)
    case stringReadOutOfBounds(offset: UInt64)
    case invalidCString(offset: UInt64)
    case byteSwapRequiredButNotImplemented
    case noObjectiveCMetadataFound

    // We need to provide a custom == because the .failedToOpenFile case
    // has an associated value of type Error, which is not Equatable.
    // We'll compare other cases directly and consider two .failedToOpenFile errors
    // unequal unless we compare their underlying properties (which is complex).
    // For our specific need (checking if error == .noObjectiveCMetadataFound),
    // this implementation is sufficient.
    static func == (lhs: MachOParseError, rhs: MachOParseError) -> Bool {
        switch (lhs, rhs) {
        case (.fileNotFound(let p1), .fileNotFound(let p2)): return p1 == p2
        case (.failedToGetFileSize(let p1), .failedToGetFileSize(let p2)): return p1 == p2
        case (.mmapFailed(let e1), .mmapFailed(let e2)): return e1 == e2
        case (.invalidMagicNumber(let m1), .invalidMagicNumber(let m2)): return m1 == m2
        case (.unsupportedArchitecture(let c1), .unsupportedArchitecture(let c2)): return c1 == c2
        case (.architectureNotFound(let c1), .architectureNotFound(let c2)): return c1 == c2
        case (.fatHeaderReadError, .fatHeaderReadError): return true
        case (.fatArchReadError, .fatArchReadError): return true
        case (.thinHeaderReadError, .thinHeaderReadError): return true
        case (.loadCommandReadError, .loadCommandReadError): return true
        case (.segmentCommandReadError, .segmentCommandReadError): return true
        case (.sectionReadError, .sectionReadError): return true
        case (.dataReadOutOfBounds(let o1, let l1, let t1), .dataReadOutOfBounds(let o2, let l2, let t2)):
             return o1 == o2 && l1 == l2 && t1 == t2
        case (.addressResolutionFailed(let v1), .addressResolutionFailed(let v2)): return v1 == v2
        case (.sectionNotFound(let seg1, let sect1), .sectionNotFound(let seg2, let sect2)):
             return seg1 == seg2 && sect1 == sect2
        case (.stringReadOutOfBounds(let o1), .stringReadOutOfBounds(let o2)): return o1 == o2
        case (.invalidCString(let o1), .invalidCString(let o2)): return o1 == o2
        case (.byteSwapRequiredButNotImplemented, .byteSwapRequiredButNotImplemented): return true
        case (.noObjectiveCMetadataFound, .noObjectiveCMetadataFound): return true
        // Special case for failedToOpenFile - consider them unequal for simplicity
        case (.failedToOpenFile, .failedToOpenFile): return false
        // Default: Cases don't match
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
                 case .fileNotFound(let path): return "File not found at path: \(path)"
                 case .failedToOpenFile(let path, let error): return "Failed to open file \(path): \(error.localizedDescription)" // Keep using localizedDescription here
                 case .failedToGetFileSize(let path): return "Failed to get file size for: \(path)"
                 case .mmapFailed(let error): return "Memory mapping failed: \(error)"
                 case .invalidMagicNumber(let magic): return String(format: "Invalid Mach-O magic number: 0x%X", magic)
                 case .unsupportedArchitecture(let cpuType): return "Unsupported CPU type: \(cpuTypeToString(cpuType)) (\(cpuType))"
                 case .architectureNotFound(let cpuType): return "Architecture \(cpuTypeToString(cpuType)) not found in fat binary."
                 case .fatHeaderReadError: return "Failed to read fat header."
                 case .fatArchReadError: return "Failed to read fat arch structure."
                 case .thinHeaderReadError: return "Failed to read Mach-O header."
                 case .loadCommandReadError: return "Failed to read load command."
                 case .segmentCommandReadError: return "Failed to read segment command."
                 case .sectionReadError: return "Failed to read section structure."
                 case .dataReadOutOfBounds(let offset, let length, let totalSize): return "Attempted to read \(length) bytes at offset \(offset), but data size is \(totalSize)."
                 case .addressResolutionFailed(let vmaddr): return String(format: "Failed to resolve VM address 0x%llX to a file offset.", vmaddr)
                 case .sectionNotFound(let segment, let section): return "Required section not found: \(segment)/\(section)"
                 case .stringReadOutOfBounds(let offset): return "String read out of bounds at offset \(offset)."
                 case .invalidCString(let offset): return "Invalid C string at offset \(offset)."
                 case .byteSwapRequiredButNotImplemented: return "File requires byte swapping (not implemented)."
                 case .noObjectiveCMetadataFound: return "No Objective-C class/protocol information found in this binary."
                 }
            }
        }

// MARK: - Helper for CPU Type String

func cpuTypeToString(_ cpuType: cpu_type_t) -> String {
    // Add more as needed, these are common ones
    switch cpuType {
    case CPU_TYPE_ARM: return "ARM"
    case CPU_TYPE_ARM64: return "ARM64"
    case CPU_TYPE_ARM64_32: return "ARM64_32" // Example, check actual value
    case CPU_TYPE_X86: return "X86"
    case CPU_TYPE_X86_64: return "X86_64"
    case CPU_TYPE_ANY: return "ANY"
    // Add specific check for arm64e if needed, its subtype usually distinguishes it
    default:
        // Check for arm64e via subtype if primary type is ARM64
        // let cpu_subtype_arm64e = // Define CPU_SUBTYPE_ARM64E based on headers
        // if cpuType == CPU_TYPE_ARM64 && cpuSubType == cpu_subtype_arm64e { return "ARM64E" }
        return "Unknown (\(cpuType))"
    }
}
