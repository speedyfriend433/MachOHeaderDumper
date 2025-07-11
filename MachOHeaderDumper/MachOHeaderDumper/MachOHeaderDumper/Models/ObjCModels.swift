//
//  ObjCModels.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: Models/ObjCModels.swift

import Foundation

// MARK: - Extracted Objective-C Data Models

// Represents a parsed Objective-C method
struct ObjCMethod: Identifiable, Hashable { // Added Hashable for potential Set usage later
    let id = UUID()
    let name: String // Selector name
    let typeEncoding: String
    let implementationAddress: UInt64 // VM Address of IMP
    let isClassMethod: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(typeEncoding)
        hasher.combine(isClassMethod)
        // Don't hash IMP address usually for equality
    }

    static func == (lhs: ObjCMethod, rhs: ObjCMethod) -> Bool {
        lhs.name == rhs.name && lhs.typeEncoding == rhs.typeEncoding && lhs.isClassMethod == rhs.isClassMethod
    }
}

// Represents a parsed Objective-C property
struct ObjCProperty: Identifiable, Hashable { // Added Hashable
    let id = UUID()
    let name: String
    let attributes: String // Raw attribute string

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(attributes)
    }

     static func == (lhs: ObjCProperty, rhs: ObjCProperty) -> Bool {
         lhs.name == rhs.name && lhs.attributes == rhs.attributes
     }
}

// Represents a parsed Objective-C instance variable (basic info)
struct ObjCIVar: Identifiable, Hashable { // Added Hashable
    let id = UUID()
    let name: String
    let typeEncoding: String
    let offset: UInt64 // The actual offset value
    let size: UInt32
    let alignment: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(typeEncoding)
        hasher.combine(offset)
    }

     static func == (lhs: ObjCIVar, rhs: ObjCIVar) -> Bool {
         lhs.name == rhs.name && lhs.typeEncoding == rhs.typeEncoding && lhs.offset == rhs.offset
     }
}

// Represents a parsed Objective-C protocol definition
class ObjCProtocol: Identifiable { // Use class for easier modification if needed later
    let id = UUID()
    let name: String
    var baseProtocols: [String] = []
    var instanceMethods: [ObjCMethod] = []
    var classMethods: [ObjCMethod] = []
    var optionalInstanceMethods: [ObjCMethod] = []
    var optionalClassMethods: [ObjCMethod] = []
    var instanceProperties: [ObjCProperty] = []
    var classProperties: [ObjCProperty] = [] // Added

    init(name: String) {
        self.name = name
    }
}

// Represents a parsed Objective-C class definition
class ObjCClass: Identifiable { // Use class to allow modification during parsing passes
    let id = UUID()
    let name: String
    var superclassName: String? // Resolved name
    var instanceMethods: [ObjCMethod] = []
    var classMethods: [ObjCMethod] = []
    var properties: [ObjCProperty] = [] // Instance properties
    var classProperties: [ObjCProperty] = [] // Added
    var ivars: [ObjCIVar] = []
    var adoptedProtocols: [String] = []

    // Metadata
    let vmAddress: UInt64 // Address where class object was found
    var metaclassVMAddress: UInt64? = nil // Address of metaclass if resolved
    let isSwiftClass: Bool // Set during initial parsing

    // --- Temporary storage for 2-pass parsing ---
    private var _tempSuperclassPtr: UInt64?
    func setTemporarySuperclassPointer(_ ptr: UInt64?) { _tempSuperclassPtr = ptr }
    func getTemporarySuperclassPointer() -> UInt64? { return _tempSuperclassPtr }
    func clearTemporarySuperclassPointer() { _tempSuperclassPtr = nil }
    // --- End Temporary Storage ---

    init(name: String, vmAddress: UInt64, superclassName: String? = nil, isSwift: Bool = false) {
        self.name = name
        self.vmAddress = vmAddress
        self.superclassName = superclassName // Initial superclass name might be nil or external
        self.isSwiftClass = isSwift
    }
}

// Container for category info before merging
struct ExtractedCategory { // Use struct here, copy semantics are fine
    let id = UUID() // Make it Identifiable if needed for UI lists
    let name: String // Category name
    var className: String // Name of class being categorized (Mutable for Pass 2 resolution)
    var instanceMethods: [ObjCMethod] = []
    var classMethods: [ObjCMethod] = []
    var protocols: [String] = []
    var instanceProperties: [ObjCProperty] = []
    var classProperties: [ObjCProperty] = []

    // --- Temporary storage for 2-pass parsing ---
    private var _tempTargetClassPtr: UInt64?
    mutating func setTemporaryTargetClassPointer(_ ptr: UInt64?) { _tempTargetClassPtr = ptr }
    // Make it non-mutating if accessing from non-mutating context, but needs var category
    func getTemporaryTargetClassPointer() -> UInt64? { return _tempTargetClassPtr }
    mutating func clearTemporaryTargetClassPointer() { _tempTargetClassPtr = nil }
    // --- End Temporary Storage ---

    // Initializer needs className to be mutable
     init(name: String, className: String, targetClassPtr: UInt64? = nil) {
         self.name = name
         self.className = className
         self._tempTargetClassPtr = targetClassPtr
     }
}

// Container for all extracted metadata
struct ExtractedMetadata {
    var classes: [String: ObjCClass] = [:]
    var protocols: [String: ObjCProtocol] = [:]
    var categories: [ExtractedCategory] = [] // Store parsed categories
    var selectorReferences: [SelectorReference] = []
}

// Selector Reference struct
struct SelectorReference: Identifiable, Hashable {
    let id = UUID()
    let selectorName: String
    let referenceAddress: UInt64 // VM Address *of the pointer* in __objc_selrefs
    func hash(into hasher: inout Hasher) { hasher.combine(selectorName); hasher.combine(referenceAddress) }
    static func == (lhs: SelectorReference, rhs: SelectorReference) -> Bool { lhs.selectorName == rhs.selectorName && lhs.referenceAddress == rhs.referenceAddress }
}


// --- Add helper methods using private vars instead of associated objects ---
// Private vars are now directly inside ObjCClass and ExtractedCategory definitions above.
