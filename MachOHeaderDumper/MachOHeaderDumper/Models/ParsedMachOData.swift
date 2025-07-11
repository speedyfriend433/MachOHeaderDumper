//
//  ParsedMachOData.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation
import MachO // Or rely on manual definitions


// --- Add explicit UInt32 constant definitions ---
// These mirror <mach-o/loader.h>
let MH_OBJECT: UInt32 = 0x1
let MH_EXECUTE: UInt32 = 0x2
let MH_FVMLIB: UInt32 = 0x3
let MH_CORE: UInt32 = 0x4
let MH_PRELOAD: UInt32 = 0x5
let MH_DYLIB: UInt32 = 0x6
let MH_DYLINKER: UInt32 = 0x7
let MH_BUNDLE: UInt32 = 0x8
let MH_DYLIB_STUB: UInt32 = 0x9
let MH_DSYM: UInt32 = 0xa
let MH_KEXT_BUNDLE: UInt32 = 0xb

// Flags (add more as needed from flagsToString)
let MH_NOUNDEFS: UInt32 = 0x1
let MH_INCRLINK: UInt32 = 0x2
let MH_DYLDLINK: UInt32 = 0x4
let MH_BINDATLOAD: UInt32 = 0x8
let MH_PREBOUND: UInt32 = 0x10
let MH_SPLIT_SEGS: UInt32 = 0x20
let MH_LAZY_INIT: UInt32 = 0x40
let MH_TWOLEVEL: UInt32 = 0x80
let MH_FORCE_FLAT: UInt32 = 0x100
let MH_NOMULTIDEFS: UInt32 = 0x200
let MH_NOFIXPREBINDING: UInt32 = 0x400
let MH_PREBINDABLE: UInt32 = 0x800
let MH_ALLMODSBOUND: UInt32 = 0x1000
let MH_SUBSECTIONS_VIA_SYMBOLS: UInt32 = 0x2000
let MH_CANONICAL: UInt32 = 0x4000
let MH_WEAK_DEFINES: UInt32 = 0x8000
let MH_BINDS_TO_WEAK: UInt32 = 0x10000
let MH_ALLOW_STACK_EXECUTION: UInt32 = 0x20000
let MH_ROOT_SAFE: UInt32 = 0x40000
let MH_SETUID_SAFE: UInt32 = 0x80000
let MH_NO_REEXPORTED_DYLIBS: UInt32 = 0x100000
let MH_PIE: UInt32 = 0x200000
let MH_DEAD_STRIPPABLE_DYLIB: UInt32 = 0x400000
let MH_HAS_TLV_DESCRIPTORS: UInt32 = 0x800000
let MH_NO_HEAP_EXECUTION: UInt32 = 0x1000000
let MH_APP_EXTENSION_SAFE: UInt32 = 0x02000000

// CPU Subtype Mask (from <mach/machine.h>)
let CPU_SUBTYPE_MASK: UInt32 = 0xff000000 // ABI/features
// --- ADDED: Global Nlist Type Defines ---
// Defines for n_type field (from <mach-o/nlist.h>)
let N_UNDF: UInt8 = 0x0  // undefined, n_sect == NO_SECT
let N_ABS: UInt8 = 0x2   // absolute, n_sect == NO_SECT
let N_SECT: UInt8 = 0xe  // defined in section number n_sect
let N_PBUD: UInt8 = 0xc  // prebound undefined (defined in a dylib)
let N_INDR: UInt8 = 0xa  // indirect
// Masks for n_type
let N_TYPE: UInt8 = 0x1e // Mask for type bits
let N_STAB: UInt8 = 0xe0 // Mask for STAB debugging bits
let N_EXT: UInt8 = 0x01  // External symbol bit, set OR'ed with type
// --- End added constants ---

// MARK: - Parsed Data Structures

struct ParsedSection {
    let command: section_64
    let name: String // Pre-calculated name
    let segmentName: String // Pre-calculated name

    init(command: section_64) {
        self.command = command
        // Use the helper defined in the manual struct definition or directly access if using MachO module
        #if !canImport(MachO) || swift(>=6.0)
        self.name = command.sectionName
        self.segmentName = command.segmentName
        #else
        // If using MachO module, access might be direct pointer math or similar helpers provided by Apple
        self.name = withUnsafePointer(to: command.sectname) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) } }
        self.segmentName = withUnsafePointer(to: command.segname) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) } }
        #endif
    }
}

struct ParsedSegment {
    let command: segment_command_64
    let sections: [ParsedSection]
    let name: String // Pre-calculated name

    init(command: segment_command_64, sections: [ParsedSection]) {
        self.command = command
        self.sections = sections
        #if !canImport(MachO) || swift(>=6.0)
        self.name = command.segmentName
        #else
        self.name = withUnsafePointer(to: command.segname) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) } }
        #endif
    }
}

// FIX: Add Equatable conformance
struct Symbol: Equatable, Hashable {
    let name: String
    let type: UInt8
    let sectionNumber: UInt8
    let description: UInt16
    let value: UInt64
    let isExternal: Bool
    // Swift can synthesize Equatable for structs whose members are all Equatable.
}

struct DynamicSymbolTableInfo {
    let localSymbolsRange: Range<UInt32>?      // ilocalsym ..< ilocalsym + nlocalsym
    let externalDefinedSymbolsRange: Range<UInt32>? // iextdefsym ..< iextdefsym + nextdefsym
    let undefinedSymbolsRange: Range<UInt32>?   // iundefsym ..< iundefsym + nundefsym
    // Add other fields like indirect symbol info if needed
    let indirectSymbolsOffset: UInt32?
    let indirectSymbolsCount: UInt32?
}

// --- Main Parsed Data Struct ---
struct ParsedMachOData {
    let fileURL: URL
    let dataRegion: UnsafeRawBufferPointer
    let header: mach_header_64
    // let segments: [ParsedSegment] // Superseded by loadCommands
    let baseAddress: UInt64
    let isSourceByteSwapped: Bool
    let encryptionInfo: [UInt32: (offset: UInt32, size: UInt32)]
    let uuid: UUID?
    let symbols: [Symbol]?
    let dynamicSymbolInfo: DynamicSymbolTableInfo?

    // --- Added ---
    let loadCommands: [ParsedLoadCommand]
    let dyldInfo: ParsedDyldInfo? // Store the fully parsed dyld info// Store all parsed load commands
    let foundStrings: [FoundString]?
    let functionStarts: [FunctionStart]?

    // --- Convenience Accessors ---
    // Get segments easily from load commands
    var segments: [ParsedSegment] {
        loadCommands.compactMap {
            if case .segment64(let cmd, let sections) = $0 {
                return ParsedSegment(command: cmd, sections: sections)
            }
            return nil
        }
    }

    func section(segmentName: String, sectionName: String) -> ParsedSection? {
         for case .segment64(_, let sections) in loadCommands {
             if let segment = sections.first?.segmentName, segment == segmentName {
                 if let section = sections.first(where: { $0.name == sectionName }) {
                     return section
                 }
             }
         }
         // Check across all segments if name match wasn't enough
         for case .segment64(_, let sections) in loadCommands {
            if let section = sections.first(where: { $0.segmentName == segmentName && $0.name == sectionName }) {
                 return section
             }
         }
         return nil
     }

    /// Helper to get the file offset range for a given section.
    func fileRange(for section: ParsedSection) -> Range<UInt64>? {
        let start = UInt64(section.command.offset)
        let end = start + section.command.size
        guard end >= start else { return nil } // Avoid invalid range
        return start..<end
    }

     /// Helper to get the VM address range for a given section.
     func vmRange(for section: ParsedSection) -> Range<UInt64>? {
         let start = section.command.addr
         let end = start + section.command.size
         guard end >= start else { return nil }
         return start..<end
     }

    /// Checks if the binary is likely encrypted based on LC_ENCRYPTION_INFO_64.
    var isEncrypted: Bool {
        // cryptid == 0 means not encrypted, cryptid == 1 means encrypted.
        return encryptionInfo.keys.contains(where: { $0 == 1 })
    }

// --- Added: Header Info Formatting ---
    var formattedHeaderInfo: String {
        var info = """
        Magic: 0x\(String(header.magic, radix: 16)) (\(header.magic == MH_MAGIC_64 ? "MH_MAGIC_64" : "Other"))
        CPU Type: \(cpuTypeToString(header.cputype)) (\(header.cputype))
        CPU Subtype: \(header.cpusubtype) \(cpuSubtypeToString(header.cputype, header.cpusubtype))
        File Type: \(fileTypeToString(header.filetype)) (\(header.filetype))
        Load Cmds: \(header.ncmds) (\(header.sizeofcmds) bytes)
        Flags: 0x\(String(header.flags, radix: 16)) (\(flagsToString(header.flags)))
        """
        if let uuid = self.uuid {
            info += "\nUUID: \(uuid.uuidString)"
        }
        return info
    }
}

extension ParsedMachOData {
    
    /// Finds the symbol corresponding to the address specified by LC_MAIN.
    /// This is typically the `start` function in the C runtime.
    /// Returns nil if LC_MAIN or the corresponding symbol isn't found.
    func findCRTEntryPointSymbol() -> Symbol? {
        // 1. Find the LC_MAIN command
        guard let mainCmdCase = self.loadCommands.first(where: {
            if case .main = $0 { return true } else { return false }
        }), case .main(let mainCmdData) = mainCmdCase else {
            return nil // LC_MAIN not found
        }
        
        // 2. Find the __TEXT segment to calculate the VM address
        guard let textSegment = self.segments.first(where: { $0.name == "__TEXT" }) else {
            return nil // __TEXT segment needed for base address
        }
        
        // 3. Calculate the target VM Address
        // entryoff is the offset *from the start of the file* to the entry code.
        // The symbol's value (n_value) should be the VM address.
        // We need to find the symbol whose address corresponds to where entryoff lands.
        // Simpler: Often the symbol's value directly matches textSegment.vmaddr + mainCmdData.entryoff
        // However, ASLR makes direct calculation hard.
        // A more reliable way is to find the symbol whose value matches the expected address
        // OR directly search for common names like `start`.
        
        // Let's try finding the symbol by address first (less reliable due to ASLR in symbol values)
        // let entryVMAddr = textSegment.command.vmaddr + mainCmdData.entryoff // This isn't quite right for symbol value matching
        
        // Let's try finding the symbol by common names first.
        let possibleNames = ["start", "_start"] // Common CRT entry names
        if let symbols = self.symbols {
            for name in possibleNames {
                if let symbol = symbols.first(where: { $0.name == name && ($0.type == N_SECT || $0.type == N_ABS) && $0.isExternal }) {
                    // Found a likely candidate by name. Verify its address roughly matches entryoff? (Difficult)
                    // Let's return the first match by name for now.
                    print("Found potential CRT entry point by name: \(name)")
                    return symbol
                }
            }
        }
        
        // Fallback: If name search fails, we could try address matching, but it's complex.
        print("Warning: Could not find common CRT entry point symbol ('start', '_start') by name.")
        return nil
    }
    
    /// Finds the symbol for the `main` function.
    /// Returns nil if not found or not suitable (e.g., undefined).
    func findMainFunctionSymbol() -> Symbol? {
        guard let symbols = self.symbols else { return nil }
        
        // Look for a symbol named "main" or "_main" that is defined in a section
        // and preferably marked as external.
        let mainSymbol = symbols.first { symbol in
            (symbol.name == "main" || symbol.name == "_main") &&
            (symbol.type == N_SECT) && // Defined in a section
            symbol.isExternal         // Likely external linkage
        }
        
        return mainSymbol
    }
}
// --- Helper functions for formatting (can go in a separate Utils file) ---
// --- Helper functions for formatting ---

func fileTypeToString(_ filetype: UInt32) -> String {
    // FIX: Compare against explicit UInt32 constants
    switch filetype {
    case MH_OBJECT: return "Object"
    case MH_EXECUTE: return "Execute"
    case MH_FVMLIB: return "FVMLib"
    case MH_CORE: return "Core"
    case MH_PRELOAD: return "Preload"
    case MH_DYLIB: return "Dylib"
    case MH_DYLINKER: return "Dylinker"
    case MH_BUNDLE: return "Bundle"
    case MH_DYLIB_STUB: return "Dylib Stub"
    case MH_DSYM: return "dSYM"
    case MH_KEXT_BUNDLE: return "Kext Bundle"
    default: return "Unknown (\(filetype))" // Show value if unknown
    }
}

func flagsToString(_ flags: UInt32) -> String {
    var parts: [String] = []
    // FIX: Ensure bitwise AND uses UInt32 constants
    if (flags & MH_NOUNDEFS) != 0 { parts.append("No Undefs") }
    if (flags & MH_INCRLINK) != 0 { parts.append("Incr Link") }
    if (flags & MH_DYLDLINK) != 0 { parts.append("Dyld Link") }
    if (flags & MH_BINDATLOAD) != 0 { parts.append("Bind at Load") }
    if (flags & MH_PREBOUND) != 0 { parts.append("Prebound") }
    if (flags & MH_SPLIT_SEGS) != 0 { parts.append("Split Segs") }
    if (flags & MH_LAZY_INIT) != 0 { parts.append("Lazy Init") }
    if (flags & MH_TWOLEVEL) != 0 { parts.append("Two Level") }
    if (flags & MH_FORCE_FLAT) != 0 { parts.append("Force Flat") }
    if (flags & MH_NOMULTIDEFS) != 0 { parts.append("No Multi Defs") }
    if (flags & MH_NOFIXPREBINDING) != 0 { parts.append("No Fix Prebinding") }
    if (flags & MH_PREBINDABLE) != 0 { parts.append("Prebindable") }
    if (flags & MH_ALLMODSBOUND) != 0 { parts.append("All Mods Bound") }
    if (flags & MH_SUBSECTIONS_VIA_SYMBOLS) != 0 { parts.append("Subsections Via Symbols") }
    if (flags & MH_CANONICAL) != 0 { parts.append("Canonical") }
    if (flags & MH_WEAK_DEFINES) != 0 { parts.append("Weak Defines") }
    if (flags & MH_BINDS_TO_WEAK) != 0 { parts.append("Binds to Weak") }
    if (flags & MH_ALLOW_STACK_EXECUTION) != 0 { parts.append("Allow Stack Exec") }
    if (flags & MH_ROOT_SAFE) != 0 { parts.append("Root Safe") }
    if (flags & MH_SETUID_SAFE) != 0 { parts.append("SetUID Safe") }
    if (flags & MH_NO_REEXPORTED_DYLIBS) != 0 { parts.append("No Reexported Dylibs") }
    if (flags & MH_PIE) != 0 { parts.append("PIE") }
    if (flags & MH_DEAD_STRIPPABLE_DYLIB) != 0 { parts.append("Dead Strippable Dylib") }
    if (flags & MH_HAS_TLV_DESCRIPTORS) != 0 { parts.append("Has TLV Descriptors") }
    if (flags & MH_NO_HEAP_EXECUTION) != 0 { parts.append("No Heap Exec") }
    if (flags & MH_APP_EXTENSION_SAFE) != 0 { parts.append("App Extension Safe") }
    // Add any other flags as needed...
    return parts.isEmpty ? "None" : parts.joined(separator: " | ")
}


func cpuSubtypeToString(_ cputype: cpu_type_t, _ subtype: cpu_subtype_t) -> String {
    // FIX: Cast subtype to UInt32 for bitwise operations with the mask
    let featureBits = UInt32(subtype) & CPU_SUBTYPE_MASK // Mask is already UInt32
    let typeBits = UInt32(subtype) & ~CPU_SUBTYPE_MASK // Mask out feature bits

    // Decode specific subtypes based on cputype if desired
    // Example for ARM64:
    if cputype == CPU_TYPE_ARM64 {
         // Constants from <mach/machine.h> or <mach-o/fat.h> (as Int32 usually)
         let CPU_SUBTYPE_ARM64_ALL: Int32 = 0
         let CPU_SUBTYPE_ARM64_V8: Int32 = 1
         let CPU_SUBTYPE_ARM64E: Int32 = 2

         switch Int32(typeBits) { // Compare base type as Int32
             case CPU_SUBTYPE_ARM64_ALL: return "ARM64_ALL" + (featureBits != 0 ? " + Features" : "")
             case CPU_SUBTYPE_ARM64_V8: return "ARM64_V8" + (featureBits != 0 ? " + Features" : "")
             case CPU_SUBTYPE_ARM64E: return "ARM64E" + (featureBits != 0 ? " + Features" : "") // Pointer Auth, etc.
             default: break
         }
    }
    // Add cases for CPU_TYPE_X86_64 etc. if needed

    // Fallback generic display
    return "(Type: \(typeBits), Features: 0x\(String(featureBits, radix: 16)))"
}


