//
//  ObjCRuntimeStructs.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation

// MARK: - Objective-C Runtime Structures (Binary Layout)
// These structs represent the layout *in the Mach-O file*.
// They are based on objc4 source (e.g., objc-runtime-new.h) but simplified.
// Sizes and alignments MUST be correct for the target architecture (arm64).
// We assume pointers are 64-bit VM addresses.

// --- List Headers ---

// Describes a list of items (methods, properties, protocols)
struct objc_list_header_t {
    let entsize_and_flags: UInt32 // Lower bits are entsize, upper bits are flags
    let count: UInt32

    // Size of each element in the list (usually includes the pointer size itself if it's a list of pointers)
    var elementSize: UInt32 { entsize_and_flags }
    // var elementSize: UInt32 { entsize_and_flags & 0xFFFF_FFFF } // Often just sizeof(void*) or struct size
    var countValue: UInt32 { count }
}

// --- Core Structures ---

// Read-Only Class Data (as found in __objc_const section)
struct class_ro_t {
    let flags: UInt32
    let instanceStart: UInt32
    let instanceSize: UInt32
    let reserved: UInt32 // Padding on 64-bit
    let ivarLayout: UInt64 // VM Address or 0
    let name: UInt64       // VM Address to CString
    let baseMethodList: UInt64 // VM Address to method_list_t or 0
    let baseProtocols: UInt64  // VM Address to protocol_list_t or 0
    let ivars: UInt64          // VM Address to ivar_list_t or 0
    let weakIvarLayout: UInt64 // VM Address or 0
    let baseProperties: UInt64 // VM Address to property_list_t or 0
    static let RO_META: UInt32 = (1 << 0)          // class is a metaclass
    static let RO_ROOT: UInt32 = (1 << 1)          // class is a root class
    static let RO_HAS_CXX_STRUCTORS: UInt32 = (1 << 2) // class has .cxx_construct/.cxx_destruct implementations
    // Swift related flags (check source for confirmation/stability)
    static let RO_IS_SWIFT: UInt32 = (1 << 3)      // class is Swift class
    static let RO_IS_SWIFT_STABLE: UInt32 = (1 << 4) // Swift class with stable ABI? (Check meaning)
    var isSwiftClass: Bool { (flags & class_ro_t.RO_IS_SWIFT) != 0 }

    // Note: Actual structure might have more fields depending on objc4 version. Adapt as needed.
}

// Method Entry
struct method_t {
    let name: UInt64  // VM Address to CString (Selector Name)
    let types: UInt64 // VM Address to CString (Type Encoding)
    let imp: UInt64   // VM Address to Implementation (IMP)
}

// Property Entry
struct property_t {
    let name: UInt64       // VM Address to CString
    let attributes: UInt64 // VM Address to CString
}

// Protocol Entry
struct protocol_t {
    let mangledName: UInt64      // VM Address to CString (Usually same as name) - ISA pointer historically? Check objc4 source. Often 0 now.
    let name: UInt64           // VM Address to CString
    let protocols: UInt64      // VM Address to protocol_list_t (protocols this protocol conforms to)
    let instanceMethods: UInt64 // VM Address to method_list_t
    let classMethods: UInt64    // VM Address to method_list_t
    let optionalInstanceMethods: UInt64 // VM Address to method_list_t
    let optionalClassMethods: UInt64    // VM Address to method_list_t
    let instanceProperties: UInt64    // VM Address to property_list_t
    // Add extended method types, etc. based on flags/objc4 version if needed
}

// Instance Variable Entry
struct ivar_t {
    // **REFINED**: This field *points* to the location where the offset of the ivar
    // is stored (usually in the class struct). This pointer must be resolved,
    // then the UInt64 offset value read from that resolved location.
    let offset_ptr: UInt64 // VM Address *pointing to* the ivar's offset value within the instance layout
    let name: UInt64       // VM Address to CString
    let type: UInt64       // VM Address to CString (Type Encoding)
    let alignment_raw: UInt32 // Alignment = 1 << alignment_raw
    let size: UInt32
}


// Category Entry (Simplified)
struct category_t {
    let name: UInt64            // VM Address to CString (Category name)
    let classRef: UInt64        // VM Address to the class this category extends
    let instanceMethods: UInt64 // VM Address to method_list_t
    let classMethods: UInt64    // VM Address to method_list_t
    let protocols: UInt64       // VM Address to protocol_list_t
    let instanceProperties: UInt64 // VM Address to property_list_t
    // ... potentially more fields like classProperties_t
}

// Pointer size constant for clarity
let POINTER_SIZE = MemoryLayout<UInt64>.size
