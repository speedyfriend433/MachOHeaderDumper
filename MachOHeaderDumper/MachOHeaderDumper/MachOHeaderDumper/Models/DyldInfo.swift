//
//  DyldInfo.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation
import MachO

// MARK: - Dyld Opcode Structures

// FIX: Add Equatable
struct RebaseOperation: Identifiable, Equatable {
    let id = UUID()
    let segmentIndex: Int
    let segmentOffset: UInt64
    let type: UInt8
    var typeDescription: String { RebaseOperation.rebaseTypeToString(type) }

    static func rebaseTypeToString(_ type: UInt8) -> String {
        switch Int32(type) {
        case REBASE_TYPE_POINTER: return "POINTER"
        case REBASE_TYPE_TEXT_ABSOLUTE32: return "TEXT_ABS32"
        case REBASE_TYPE_TEXT_PCREL32: return "TEXT_PCREL32"
        default: return "UNKNOWN (\(type))"
        }
    }

    // FIX: Ensure == is INSIDE the struct definition
    static func == (lhs: RebaseOperation, rhs: RebaseOperation) -> Bool {
        return lhs.segmentIndex == rhs.segmentIndex &&
               lhs.segmentOffset == rhs.segmentOffset &&
               lhs.type == rhs.type
    }
}

// FIX: Add Equatable
struct BindOperation: Identifiable, Equatable {
    let id = UUID()
    let segmentIndex: Int
    let segmentOffset: UInt64
    let type: UInt8
    let flags: UInt8
    let addend: Int64
    let dylibOrdinal: Int
    let symbolName: String
    var isWeakImport: Bool { (flags & BIND_SYMBOL_FLAGS_WEAK_IMPORT) != 0 }
    var typeDescription: String { BindOperation.bindTypeToString(type) }

    static func bindTypeToString(_ type: UInt8) -> String {
       switch Int32(type) {
       case BIND_TYPE_POINTER: return "POINTER"
       case BIND_TYPE_TEXT_ABSOLUTE32: return "TEXT_ABS32"
       case BIND_TYPE_TEXT_PCREL32: return "TEXT_PCREL32"
       default: return "UNKNOWN (\(type))"
       }
    }
    var ordinalDescription: String {
        switch dylibOrdinal {
        case BIND_SPECIAL_DYLIB_SELF: return "SELF"
        case BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE: return "MAIN_EXEC"
        case BIND_SPECIAL_DYLIB_FLAT_LOOKUP: return "FLAT"
        case let ord where ord > 0: return "Dylib #\(ord)"
        default: return "Special (\(dylibOrdinal))"
        }
    }

     // FIX: Ensure == is INSIDE the struct definition
     static func == (lhs: BindOperation, rhs: BindOperation) -> Bool {
         return lhs.segmentIndex == rhs.segmentIndex &&
                lhs.segmentOffset == rhs.segmentOffset &&
                lhs.type == rhs.type &&
                lhs.flags == rhs.flags &&
                lhs.addend == rhs.addend &&
                lhs.dylibOrdinal == rhs.dylibOrdinal &&
                lhs.symbolName == rhs.symbolName
     }
}

func == (lhs: BindOperation, rhs: BindOperation) -> Bool {
         return lhs.segmentIndex == rhs.segmentIndex &&
                lhs.segmentOffset == rhs.segmentOffset &&
                lhs.type == rhs.type &&
                lhs.flags == rhs.flags &&
                lhs.addend == rhs.addend &&
                lhs.dylibOrdinal == rhs.dylibOrdinal &&
                lhs.symbolName == rhs.symbolName
     }


// MARK: - Dyld Export Constants (from dyld source / dyldinfo.h)

let EXPORT_SYMBOL_FLAGS_KIND_MASK: UInt64 = 0x03
let EXPORT_SYMBOL_FLAGS_KIND_REGULAR: UInt64 = 0x00
let EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL: UInt64 = 0x01
let EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE: UInt64 = 0x02
let EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION: UInt64 = 0x04
let EXPORT_SYMBOL_FLAGS_REEXPORT: UInt64 = 0x08
let EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER: UInt64 = 0x10
// MARK: - Exported Symbol Structure

struct ExportedSymbol: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let flags: UInt64
    let address: UInt64
    // Optional fields populated based on flags:
    let otherOffset: UInt64? // e.g., Resolver offset if STUB_AND_RESOLVER is set
    let importName: String? // Symbol name in target dylib if REEXPORT
    let importLibraryOrdinal: Int? // Dylib ordinal if REEXPORT

    var kind: String {
        switch flags & EXPORT_SYMBOL_FLAGS_KIND_MASK {
        case EXPORT_SYMBOL_FLAGS_KIND_REGULAR: return "Regular"
        case EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL: return "ThreadLocal"
        case EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE: return "Absolute"
        default: return "UnknownKind"
        }
    }
    var isWeakDefined: Bool { (flags & EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION) != 0 }
    var isReExport: Bool { (flags & EXPORT_SYMBOL_FLAGS_REEXPORT) != 0 }
    var hasStubAndResolver: Bool { (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER) != 0 }

     // Make Equatable (ignore UUID)
     static func == (lhs: ExportedSymbol, rhs: ExportedSymbol) -> Bool {
         lhs.name == rhs.name &&
         lhs.flags == rhs.flags &&
         lhs.address == rhs.address &&
         lhs.otherOffset == rhs.otherOffset &&
         lhs.importName == rhs.importName &&
         lhs.importLibraryOrdinal == rhs.importLibraryOrdinal
     }
}
// MARK: - Update ParsedDyldInfo

// FIX: Add Equatable conformance was already done
struct ParsedDyldInfo: Equatable {
    var rebases: [RebaseOperation] = []
    var binds: [BindOperation] = []
    var weakBinds: [BindOperation] = []
    var lazyBinds: [BindOperation] = []
    var exports: [ExportedSymbol] = []
}

// MARK: - Dyld Opcode Constants (from <mach-o/fixup-chains.h> / <mach-o/loader.h> / dyld source)

// Rebase types
let REBASE_TYPE_POINTER: Int32 = 1
let REBASE_TYPE_TEXT_ABSOLUTE32: Int32 = 2
let REBASE_TYPE_TEXT_PCREL32: Int32 = 3

// Rebase opcodes
let REBASE_OPCODE_MASK: UInt8 = 0xF0
let REBASE_IMMEDIATE_MASK: UInt8 = 0x0F
let REBASE_OPCODE_DONE: UInt8 = 0x00
let REBASE_OPCODE_SET_TYPE_IMM: UInt8 = 0x10
let REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: UInt8 = 0x20
let REBASE_OPCODE_ADD_ADDR_ULEB: UInt8 = 0x30
let REBASE_OPCODE_ADD_ADDR_IMM_SCALED: UInt8 = 0x40
let REBASE_OPCODE_DO_REBASE_IMM_TIMES: UInt8 = 0x50
let REBASE_OPCODE_DO_REBASE_ULEB_TIMES: UInt8 = 0x60
let REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB: UInt8 = 0x70
let REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: UInt8 = 0x80

// Bind types
let BIND_TYPE_POINTER: Int32 = 1
let BIND_TYPE_TEXT_ABSOLUTE32: Int32 = 2
let BIND_TYPE_TEXT_PCREL32: Int32 = 3

// Bind opcodes
let BIND_OPCODE_MASK: UInt8 = 0xF0
let BIND_IMMEDIATE_MASK: UInt8 = 0x0F
let BIND_OPCODE_DONE: UInt8 = 0x00
let BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: UInt8 = 0x10
let BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB: UInt8 = 0x20
let BIND_OPCODE_SET_DYLIB_SPECIAL_IMM: UInt8 = 0x30
let BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: UInt8 = 0x40
let BIND_OPCODE_SET_TYPE_IMM: UInt8 = 0x50
let BIND_OPCODE_SET_ADDEND_SLEB: UInt8 = 0x60
let BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: UInt8 = 0x70
let BIND_OPCODE_ADD_ADDR_ULEB: UInt8 = 0x80
let BIND_OPCODE_DO_BIND: UInt8 = 0x90
let BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB: UInt8 = 0xA0
let BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED: UInt8 = 0xB0
let BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: UInt8 = 0xC0
// Missing? BIND_OPCODE_THREADED = 0xD0

// Bind symbol flags
let BIND_SYMBOL_FLAGS_WEAK_IMPORT: UInt8 = 0x1
let BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION: UInt8 = 0x8

// Bind special dylib ordinals
let BIND_SPECIAL_DYLIB_SELF: Int = 0
let BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE: Int = -1
let BIND_SPECIAL_DYLIB_FLAT_LOOKUP: Int = -2
