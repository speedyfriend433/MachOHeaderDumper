//
//  MachOStructures.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation
import MachO // Attempt to use system headers first

// MARK: - Mach-O Data Structures (Manual Definitions if MachO module not available)
// These mirror <mach-o/loader.h>, <mach-o/fat.h>. Ensure they match the target system.
typealias cpu_type_t = Int32
typealias cpu_subtype_t = Int32
typealias vm_prot_t = Int32

// LC_MAIN command structure
struct entry_point_command {
    let cmd: UInt32       // LC_MAIN
    let cmdsize: UInt32   // sizeof(entry_point_command)
    let entryoff: UInt64  // file offset of main() -> Note: This is offset to the *start* code, not necessarily main() symbol
    let stacksize: UInt64 // if not zero, initial stack size
}

// --- Updated ParsedLoadCommand Enum ---
enum ParsedLoadCommand {
    case segment64(segment_command_64, [ParsedSection])
    case uuid(uuid_command)
        case symtab(symtab_command)
        case dysymtab(dysymtab_command)
        case encryptionInfo64(encryption_info_command_64)
        case loadDylib(String, dylib)
        case idDylib(String, dylib)
        case loadDylinker(String)
        case sourceVersion(source_version_command)
        case versionMin(version_min_command, String)
        case buildVersion(build_version_command)
        case main(entry_point_command)
        case functionStarts(linkedit_data_command)
        case dataInCode(linkedit_data_command)
        case codeSignature(linkedit_data_command)
        case dyldInfo(dyld_info_command)
        case unknown(cmd: UInt32, cmdsize: UInt32)

    var description: String {
             switch self {
             case .segment64(let cmd, let sections):
                 // FIX: Use the standalone helper function consistently
                 let segName = stringFromCChar16Tuple(cmd.segname)
                 return "LC_SEGMENT_64 (\(segName), \(sections.count) sections)"
         case .uuid(let cmd): return "LC_UUID (\(UUID(uuid: cmd.uuid).uuidString))"
                  case .symtab: return "LC_SYMTAB"
         case .dysymtab: return "LC_DYSYMTAB"
                  case .encryptionInfo64(let cmd): return "LC_ENCRYPTION_INFO_64 (ID: \(cmd.cryptid))"
                  case .loadDylib(let path, _): return "LC_LOAD_DYLIB (\(path))"
                  case .idDylib(let path, _): return "LC_ID_DYLIB (\(path))"
                  case .loadDylinker(let path): return "LC_LOAD_DYLINKER (\(path))"
                  case .sourceVersion(let cmd): return "LC_SOURCE_VERSION (\(formatVersionPacked64(cmd.version)))"
                  case .versionMin(_, let platform): return "LC_VERSION_MIN_\(platform)"
                  case .buildVersion(let cmd): return "LC_BUILD_VERSION (Plat: \(platformToString(cmd.platform)), MinOS: \(formatVersionPacked32(cmd.minos)))"
                  case .main(let cmd): return "LC_MAIN (EntryOff: \(cmd.entryoff), StackSize: \(cmd.stacksize))"
                  case .functionStarts: return "LC_FUNCTION_STARTS"
                  case .dataInCode: return "LC_DATA_IN_CODE"
                  case .codeSignature: return "LC_CODE_SIGNATURE"
                  case .dyldInfo: return "LC_DYLD_INFO_ONLY"
                  case .unknown(let cmd, _): return String(format: "LC_UNKNOWN (0x%X)", cmd)
                  }
              }
         }

// Helper to format X.Y.Z packed version
func formatVersionPacked32(_ packed: UInt32) -> String {
    let major = (packed >> 16) & 0xFFFF
    let minor = (packed >> 8) & 0xFF
    let patch = packed & 0xFF
    return "\(major).\(minor).\(patch)"
}
// Helper to format A.B.C.D.E packed version
func formatVersionPacked64(_ packed: UInt64) -> String {
    let a = (packed >> 40) & 0xFFFFFF // 24 bits
    let b = (packed >> 30) & 0x3FF   // 10 bits
    let c = (packed >> 20) & 0x3FF   // 10 bits
    let d = (packed >> 10) & 0x3FF   // 10 bits
    let e = packed & 0x3FF           // 10 bits
    return "\(a).\(b).\(c).\(d).\(e)"
}

// Platform defines for LC_BUILD_VERSION (approximate values, check headers)
let PLATFORM_MACOS: UInt32 = 1
let PLATFORM_IOS: UInt32 = 2
let PLATFORM_TVOS: UInt32 = 3
let PLATFORM_WATCHOS: UInt32 = 4
let PLATFORM_BRIDGEOS: UInt32 = 5
let PLATFORM_MACCATALYST: UInt32 = 6
let PLATFORM_IOSSIMULATOR: UInt32 = 7

// --- ADDED: VM Protection Constants ---
// Defined as Int32 in <mach/vm_prot.h>
let VM_PROT_READ: vm_prot_t    = 0x01  /* read permission */
let VM_PROT_WRITE: vm_prot_t   = 0x02  /* write permission */
let VM_PROT_EXECUTE: vm_prot_t = 0x04  /* execute permission */
// Define others if needed (e.g., VM_PROT_COPY, VM_PROT_DEFAULT)

// Helper to format platform ID
func platformToString(_ platform: UInt32) -> String {
    // FIX: Compare against explicit UInt32 constants
    switch platform {
    case PLATFORM_MACOS: return "macOS"
    case PLATFORM_IOS: return "iOS"
    case PLATFORM_TVOS: return "tvOS"
    case PLATFORM_WATCHOS: return "watchOS"
    case PLATFORM_BRIDGEOS: return "bridgeOS"
    case PLATFORM_MACCATALYST: return "macCatalyst"
    case PLATFORM_IOSSIMULATOR: return "iOS Sim"
    default: return "Unknown (\(platform))"
    }
}

// --- ADDED: Standalone helper for C char[16] tuples ---
func stringFromCChar16Tuple(_ tuple: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)) -> String {
    withUnsafeBytes(of: tuple) { buffer -> String in
        let data = Data(buffer)
        if let termIndex = data.firstIndex(of: 0) {
            return String(data: data[..<termIndex], encoding: .ascii) ?? ""
        } else {
            return String(data: data, encoding: .ascii) ?? ""
        }
    }
}
// --- END Standalone Helper ---

// Define dylib_command structure if needed for path reading
// Based on <mach-o/loader.h>
struct dylib_command {
    let cmd: UInt32         // LC_LOAD_DYLIB, LC_ID_DYLIB, etc.
    let cmdsize: UInt32     // includes pathname string
    let dylib: dylib        // the library identification
}
struct dylib {
    let name: lc_str        // library's path name, offset from start of dylib_command
    let timestamp: UInt32   // library's build time stamp
    let current_version: UInt32 // library's current version number
    let compatibility_version: UInt32 // library's compatibility vers number
}
typealias lc_str = UInt32 // Offset from beginning of load command

// --- ADDED: Make sure dyld_info_command is defined globally or accessible ---
// LC_DYLD_INFO / LC_DYLD_INFO_ONLY Command
internal struct dyld_info_command { // Added internal explicitly
    let cmd: UInt32
    let cmdsize: UInt32
    let rebase_off: UInt32
    let rebase_size: UInt32
    let bind_off: UInt32
    let bind_size: UInt32
    let weak_bind_off: UInt32
    let weak_bind_size: UInt32
    let lazy_bind_off: UInt32
    let lazy_bind_size: UInt32
    let export_off: UInt32
    let export_size: UInt32
}

#if !canImport(MachO) || swift(>=6.0) // Swift 6 might remove C module imports like this, adjust condition if needed

// --- Basic Types (Ensure these match C definitions) ---
typealias cpu_type_t = Int32
typealias cpu_subtype_t = Int32
typealias vm_prot_t = Int32

// --- CPU Types ---
let CPU_TYPE_ANY: cpu_type_t = -1
let CPU_TYPE_X86: cpu_type_t = 7
let CPU_TYPE_X86_64: cpu_type_t = CPU_TYPE_X86 | 0x01000000 // CPU_ARCH_ABI64
let CPU_TYPE_ARM: cpu_type_t = 12
let CPU_TYPE_ARM64: cpu_type_t = CPU_TYPE_ARM | 0x01000000 // CPU_ARCH_ABI64

// --- Magic Numbers ---
let MH_MAGIC: UInt32 = 0xfeedface
let MH_CIGAM: UInt32 = 0xcefaedfe
let MH_MAGIC_64: UInt32 = 0xfeedfacf
let MH_CIGAM_64: UInt32 = 0xcffaedfe
let FAT_MAGIC: UInt32 = 0xcafebabe
let FAT_CIGAM: UInt32 = 0xbebafeca

// Load Command Types (ensure these are defined, add if missing)
let LC_REQ_DYLD: UInt32 = 0x80000000
let LC_SEGMENT: UInt32 = 0x1
let LC_SYMTAB: UInt32 = 0x2
let LC_DYSYMTAB: UInt32 = 0xb
let LC_LOAD_DYLIB: UInt32 = 0xc
let LC_ID_DYLIB: UInt32 = 0xd
let LC_LOAD_DYLINKER: UInt32 = 0xe
let LC_UUID: UInt32 = 0x1b
let LC_VERSION_MIN_MACOSX: UInt32 = 0x24 // Added
let LC_VERSION_MIN_IPHONEOS: UInt32 = 0x25 // Added
let LC_VERSION_MIN_WATCHOS: UInt32 = 0x27 // Added
let LC_VERSION_MIN_TVOS: UInt32 = 0x2F // Added
let LC_SOURCE_VERSION: UInt32 = 0x2A // Added
let LC_SEGMENT_64: UInt32 = 0x19
let LC_ENCRYPTION_INFO_64: UInt32 = 0x2C
let LC_CODE_SIGNATURE: UInt32 = 0x1d // Added
let LC_MAIN: UInt32 = 0x28 | 0x80000000 // LC_REQ_DYLD
let LC_DATA_IN_CODE: UInt32 = 0x29 // Added
let LC_FUNCTION_STARTS: UInt32 = 0x26 // Added
let LC_DYLD_INFO_ONLY: UInt32 = 0x22 | LC_REQ_DYLD // Added (Structure defined later)
let LC_BUILD_VERSION: UInt32 = 0x32 // Modern replacement for LC_VERSION_MIN_*

// --- New Command Structs ---

// LC_VERSION_MIN_* Commands (share layout)
struct version_min_command {
    let cmd: UInt32       // LC_VERSION_MIN_MACOSX, LC_VERSION_MIN_IPHONEOS, ...
    let cmdsize: UInt32   // sizeof(struct version_min_command)
    let version: UInt32   // X.Y.Z is encoded in nibbles: XXXX.YY.ZZ
    let sdk: UInt32       // X.Y.Z is encoded in nibbles: XXXX.YY.ZZ
}

// LC_SOURCE_VERSION Command
struct source_version_command {
    let cmd: UInt32       // LC_SOURCE_VERSION
    let cmdsize: UInt32   // sizeof(struct source_version_command)
    let version: UInt64   // A.B.C.D.E packed as a24.b10.c10.d10.e10
}

// LC_FUNCTION_STARTS, LC_DATA_IN_CODE, LC_CODE_SIGNATURE (Linkedit Data Commands)
// These share the same structure, pointing to data in __LINKEDIT
struct linkedit_data_command {
    let cmd: UInt32       // LC_CODE_SIGNATURE, LC_FUNCTION_STARTS, LC_DATA_IN_CODE, etc.
    let cmdsize: UInt32   // sizeof(struct linkedit_data_command)
    let dataoff: UInt32   // file offset of data in __LINKEDIT
    let datasize: UInt32  // file size of data in __LINKEDIT
}

// LC_DYLD_INFO / LC_DYLD_INFO_ONLY Command
struct dyld_info_command {
    let cmd: UInt32           // LC_DYLD_INFO or LC_DYLD_INFO_ONLY
    let cmdsize: UInt32       // sizeof(struct dyld_info_command)
    let rebase_off: UInt32    // file offset to rebase info
    let rebase_size: UInt32   // size of rebase info
    let bind_off: UInt32      // file offset to binding info
    let bind_size: UInt32     // size of binding info
    let weak_bind_off: UInt32 // file offset to weak binding info
    let weak_bind_size: UInt32// size of weak binding info
    let lazy_bind_off: UInt32 // file offset to lazy binding info
    let lazy_bind_size: UInt32// size of lazy binding info
    let export_off: UInt32    // file offset to export info
    let export_size: UInt32   // size of export info
}

// LC_BUILD_VERSION Command
struct build_version_command {
    let cmd: UInt32        // LC_BUILD_VERSION
    let cmdsize: UInt32    // sizeof(struct build_version_command) + ntools * sizeof(struct build_tool_version)
    let platform: UInt32   // PLATFORM_MACOS, PLATFORM_IOS, etc.
    let minos: UInt32      // X.Y.Z is encoded in nibbles: XXXX.YY.ZZ
    let sdk: UInt32        // X.Y.Z is encoded in nibbles: XXXX.YY.ZZ
    let ntools: UInt32     // number of tool entries following this
    // build_tool_version tool_versions[]; // Variable size array follows
}

// --- Core Structures ---
struct mach_header {
    let magic: UInt32
    let cputype: cpu_type_t
    let cpusubtype: cpu_subtype_t
    let filetype: UInt32
    let ncmds: UInt32
    let sizeofcmds: UInt32
    let flags: UInt32
}

struct mach_header_64 {
    let magic: UInt32
    let cputype: cpu_type_t
    let cpusubtype: cpu_subtype_t
    let filetype: UInt32
    let ncmds: UInt32
    let sizeofcmds: UInt32
    let flags: UInt32
    let reserved: UInt32 // Only in 64-bit
}

struct load_command {
    let cmd: UInt32
    let cmdsize: UInt32
}

// Note: Using tuples for fixed-size C arrays like char[16]
struct segment_command_64 {
    let cmd: UInt32
    let cmdsize: UInt32
    let segname: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)
    let vmaddr: UInt64
    let vmsize: UInt64
    let fileoff: UInt64
    let filesize: UInt64
    let maxprot: vm_prot_t
    let initprot: vm_prot_t
    let nsects: UInt32
    let flags: UInt32

    var segmentName: String { Self.string(from: segname) }

    /* ... fields ... */
    // Static helper function only defined when NOT using system MachO
        static func string(from tuple: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)) -> String {
            withUnsafeBytes(of: tuple) { buffer -> String in
                let data = Data(buffer)
                if let termIndex = data.firstIndex(of: 0) {
                    return String(data: data[..<termIndex], encoding: .ascii) ?? ""
                } else {
                    return String(data: data, encoding: .ascii) ?? ""
                }
            }
        }
    }

struct section_64 {
    let sectname: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)
    let segname: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)
    let addr: UInt64
    let size: UInt64
    let offset: UInt32
    let align: UInt32
    let reloff: UInt32
    let nreloc: UInt32
    let flags: UInt32
    let reserved1: UInt32
    let reserved2: UInt32
    let reserved3: UInt32 // Added for padding

    var sectionName: String { segment_command_64.string(from: sectname) }
    var segmentName: String { segment_command_64.string(from: segname) }
}

struct fat_header {
    let magic: UInt32
    let nfat_arch: UInt32
}

struct fat_arch {
    let cputype: cpu_type_t
    let cpusubtype: cpu_subtype_t
    let offset: UInt32 // Use big-endian type or swap manually if FAT_CIGAM
    let size: UInt32   // Use big-endian type or swap manually if FAT_CIGAM
    let align: UInt32  // Use big-endian type or swap manually if FAT_CIGAM
}

// Define other structs like encryption_info_command_64, symtab_command etc. here if needed
struct encryption_info_command_64 {
    let cmd: UInt32
    let cmdsize: UInt32
    let cryptoff: UInt32
    let cryptsize: UInt32
    let cryptid: UInt32
    let pad: UInt32 // Padding for 64-bit
}

// --- Added Structures ---

// LC_UUID Command Structure
struct uuid_command {
    let cmd: UInt32       // LC_UUID
    let cmdsize: UInt32   // sizeof(uuid_command)
    let uuid: uuid_t      // 16 byte UUID (uuid_t is often defined as a tuple of 16 UInt8)
    // typealias uuid_t = (UInt8, UInt8, ..., UInt8) // 16 times
}

// LC_SYMTAB Command Structure
struct symtab_command {
    let cmd: UInt32       // LC_SYMTAB
    let cmdsize: UInt32   // sizeof(symtab_command)
    let symoff: UInt32    // symbol table offset (from start of file)
    let nsyms: UInt32     // number of symbol table entries
    let stroff: UInt32    // string table offset (from start of file)
    let strsize: UInt32   // string table size in bytes
}

// Symbol Table Entry (64-bit)
struct nlist_64 {
    let n_un: n_union     // union containing offset into string table
    let n_type: UInt8     // type flag, see below
    let n_sect: UInt8     // section number or NO_SECT
    let n_desc: UInt16    // see <mach-o/stab.h>
    let n_value: UInt64   // value of this symbol (or stab offset)

    // Helper for string table offset
    var n_strx: UInt32 { n_un.n_strx }
}

// Union for n_un field in nlist_64 (simplified, just storing offset)
// In C, this is `union { uint32_t n_strx; }`.
// Swift doesn't have direct C unions easily, store the common field.
struct n_union {
    let n_strx: UInt32 // offset into string table
}

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

// LC_DYSYMTAB Command Structure
struct dysymtab_command {
    let cmd: UInt32           // LC_DYSYMTAB
    let cmdsize: UInt32       // sizeof(dysymtab_command)
    let ilocalsym: UInt32     // index to local symbols
    let nlocalsym: UInt32     // number of local symbols
    let iextdefsym: UInt32    // index to externally defined symbols
    let nextdefsym: UInt32    // number of externally defined symbols
    let iundefsym: UInt32     // index to undefined symbols
    let nundefsym: UInt32     // number of undefined symbols
    let tocoff: UInt32        // file offset to table of contents
    let ntoc: UInt32          // number of entries in table of contents
    let modtaboff: UInt32     // file offset to module table
    let nmodtab: UInt32       // number of module table entries
    let extrefsymoff: UInt32  // offset to referenced symbol table
    let nextrefsyms: UInt32   // number of referenced symbol table entries
    let indirectsymoff: UInt32// file offset to indirect symbol table
    let nindirectsyms: UInt32 // number of indirect symbol table entries
    let extreloff: UInt32     // offset to external relocation entries
    let nextrel: UInt32       // number of external relocation entries
    let locreloff: UInt32     // offset to local relocation entries
    let nlocrel: UInt32       // number of local relocation entries
}

#endif // !canImport(MachO)
