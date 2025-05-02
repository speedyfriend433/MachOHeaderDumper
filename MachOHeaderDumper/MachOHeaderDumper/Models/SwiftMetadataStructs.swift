//
//  SwiftMetadataStructs.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: SwiftMetadataStructs.swift

import Foundation

// --- Target Type Context Descriptor Flags ---
// From Swift source (include/swift/ABI/MetadataValues.h) - Simplified
struct TypeContextDescriptorFlags {
    let value: UInt32

    // Example flags (check source for exact values/layout)
    var isGeneric: Bool { (value & 0x80) != 0 }
    var isUnique: Bool { (value & 0x40) != 0 }
    var kind: UInt8 { UInt8(value & 0x1F) } // Lower 5 bits for Kind specific format

    func kindSpecificFlags() -> UInt16 {
         return UInt16((value >> 16) & 0xFFFF)
    }

    var kindString: String {
         switch kind {
         case 0: return "Module"
         case 1: return "Extension"
         case 2: return "Anonymous"
         case 3: return "Protocol"
         case 4: return "OpaqueType"
         case 16: return "Class"       // TargetClassDescriptor Kind
         case 17: return "Struct"      // TargetStructDescriptor Kind
         case 18: return "Enum"        // TargetEnumDescriptor Kind
         default: return "Unknown (\(kind))"
         }
    }
}

// --- Base for all Type Context Descriptors ---
// Often the first fields in Class, Struct, Enum, Protocol descriptors
struct TargetContextDescriptor {
    let flags: TypeContextDescriptorFlags // Actually UInt32 in memory
    let parent: Int32 // Relative pointer (offset) to parent context (e.g., module) or 0
    // Name and AccessFunction pointers follow in specific descriptor types
}

// --- TargetClassDescriptor ---
// Simplified layout - check Swift ABI docs/source
struct TargetClassDescriptor {
    // Inherits from TargetContextDescriptor (Flags, Parent)
    let flags: UInt32 // TypeContextDescriptorFlags
    let parent: Int32 // RelativePointer<ContextDescriptor>
    let name: Int32 // RelativePointer<char> to mangled name
    let accessFunctionPtr: Int32 // RelativePointer<MetadataAccessFunction>
    let fields: Int32 // RelativePointer<FieldDescriptor>
    let superclassType: Int32 // RelativePointer<Type> or mangled name offset? Check ABI. May be 0.
    // Other fields follow: metadata negative/positive size, numImmediateMembers,
    // numFields, fieldOffsetVectorOffset, GenericParams, etc.
    // ... We only read the first few for basic info ...
}

// --- TargetStructDescriptor / TargetEnumDescriptor ---
// Similar layout to TargetClassDescriptor initially
struct TargetValueTypeDescriptor { // Common prefix for Struct/Enum
    let flags: UInt32 // TypeContextDescriptorFlags
    let parent: Int32 // RelativePointer<ContextDescriptor>
    let name: Int32 // RelativePointer<char>
    let accessFunctionPtr: Int32 // RelativePointer<MetadataAccessFunction>
    let fields: Int32 // RelativePointer<FieldDescriptor>
    // Other fields follow: numFields, fieldOffsetVectorOffset, GenericParams, etc.
}

// --- Field Descriptor (Describes fields of a class/struct/enum) ---
// Simplified - Layout depends on Generic/Non-Generic
struct FieldDescriptor {
    let mangledTypeNameOffset: Int32 // Relative offset to type name
    let superclassOffset: Int32      // Relative offset to superclass type name (if any)
    let kind: UInt16                // FieldDescriptorKind
    let fieldRecordSize: UInt16     // Size of each FieldRecord
    let numFields: UInt32           // Number of fields
    // FieldRecord fieldRecords[]; Follows immediately
}

// Simplified representation of a field record
struct FieldRecord {
    let flags: UInt32               // FieldRecordFlags
    let mangledTypeNameOffset: Int32 // Relative pointer to the field's type name
    let fieldNameOffset: Int32       // Relative pointer to the field's name (UTF8 string)
}

// --- Relative Pointer Helper ---
// Represents a relative pointer stored as Int32 offset
// Base address needs to be the address *of the pointer itself* in memory
func resolveRelativePointer(baseAddress: UInt64, relativeOffset: Int32) -> UInt64? {
    if relativeOffset == 0 { return nil }
    // Convert the relative offset (which can be negative) to Int64 for wider range
       let offset = Int64(relativeOffset)

       // Perform the addition using signed Int64 arithmetic
       // Convert the base address (location of the pointer) to Int64 temporarily
       let targetAddressSigned = Int64(bitPattern: baseAddress) &+ offset // Use overflow addition for safety

       // Convert the result back to UInt64
       // If the signed result was negative (extremely unlikely for valid addresses,
       // but possible with large negative offsets), this conversion wraps around.
       let targetAddressUnsigned = UInt64(bitPattern: targetAddressSigned)

       // Optional: Add a sanity check if needed (e.g., ensure result isn't suspiciously low)
       // guard targetAddressUnsigned > SOME_REASONABLE_LOWER_BOUND else { return nil }

       // print("      [Debug] resolveRelativePointer: Base=0x\(String(baseAddress, radix: 16)), Offset=\(offset) (0x\(String(relativeOffset, radix: 16))), Result=0x\(String(targetAddressUnsigned, radix: 16))")

       return targetAddressUnsigned
   }
// Size constants (ensure correctness for arm64)
let RELATIVE_POINTER_SIZE = MemoryLayout<Int32>.size
let TARGET_CONTEXT_DESCRIPTOR_SIZE = 8 // flags(4) + parent(4) (Approx)
