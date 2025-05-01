//
//  ObjCModels.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation

// MARK: - Extracted Objective-C Data Models

// Represents a parsed Objective-C method
struct ObjCMethod {
    let name: String // Selector name
    let typeEncoding: String
    let implementationAddress: UInt64 // VM Address of IMP
    let isClassMethod: Bool
}

// Represents a parsed Objective-C property
struct ObjCProperty {
    let name: String
    let attributes: String // Raw attribute string (e.g., "T@\"NSString\",&,N,V_myString")
    // Add parsed attributes later (nonatomic, weak, readonly etc.)
}

// Represents a parsed Objective-C instance variable
struct ObjCIVar {
    let name: String
    let typeEncoding: String
    let offset: UInt64 // Store the *actual* resolved offset value
    let size: UInt32
    let alignment: Int
}

// Represents a parsed Objective-C protocol definition
class ObjCProtocol {
    let name: String
    var baseProtocols: [String] = []
    var instanceMethods: [ObjCMethod] = []
    var classMethods: [ObjCMethod] = []
    var optionalInstanceMethods: [ObjCMethod] = []
    var optionalClassMethods: [ObjCMethod] = []
    var instanceProperties: [ObjCProperty] = []
    var classProperties: [ObjCProperty] = [] // <-- ADDED

    init(name: String) {
        self.name = name
    }
}
// Represents a parsed Objective-C class definition
class ObjCClass {
    let name: String
    var superclassName: String?
    var instanceMethods: [ObjCMethod] = []
    var classMethods: [ObjCMethod] = []
    var properties: [ObjCProperty] = [] // Instance properties
    var classProperties: [ObjCProperty] = [] // <-- ADDED
    var ivars: [ObjCIVar] = []
    var adoptedProtocols: [String] = []

    let vmAddress: UInt64
    let isSwiftClass: Bool // Keep basic Swift check (can refine later)

    // Keep track of metaclass pointer if resolved
    var metaclassVMAddress: UInt64? = nil

    init(name: String, vmAddress: UInt64, superclassName: String? = nil, isSwift: Bool = false) {
        self.name = name
        self.vmAddress = vmAddress
        self.superclassName = superclassName
        self.isSwiftClass = isSwift
    }
}

// --- Added: Category Intermediate Storage ---
// ExtractedCategory needs class properties too
struct ExtractedCategory {
    let name: String
    let className: String
    var instanceMethods: [ObjCMethod] = []
    var classMethods: [ObjCMethod] = []
    var protocols: [String] = []
    var instanceProperties: [ObjCProperty] = []
    var classProperties: [ObjCProperty] = [] // <-- ADDED
}


// Container for all extracted metadata (Add categories)
struct ExtractedMetadata {
    var classes: [String: ObjCClass] = [:]
    var protocols: [String: ObjCProtocol] = [:]
    var categories: [ExtractedCategory] = [] // Store parsed categories before merging
}
