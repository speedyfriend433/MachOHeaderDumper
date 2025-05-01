//
//  TypeDecoder.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: TypeDecoder.swift (Corrected for indirect and quotes)

import Foundation

// MARK: - Type Encoding Decoder

// FIX: Mark enum as indirect to allow recursive cases
indirect enum DecodedType {
    case `class`(name: String?) // nil name for 'id'
    case object(name: String) // Explicit class name @"NSString"
    case block
    case selector
    case char
    case uchar
    case short
    case ushort
    case int
    case uint
    case long
    case ulong
    case longlong
    case ulonglong
    case float
    case double
    case bool
    case void
    case cString // char *
    case pointer(pointee: DecodedType?) // Recursive
    case `struct`(name: String, members: [(String?, DecodedType)]?) // Recursive
    case union(name: String, members: [(String?, DecodedType)]?) // Recursive
    case array(count: Int, elementType: DecodedType) // Recursive
    case unknown(encoding: String)
    case bitfield(size: Int)
}

// FIX: This should now have a defined size as DecodedType is indirect
struct DecodedMethodSignature {
    let returnType: DecodedType
    let arguments: [DecodedType]
}

// TypeError enum remains the same...
enum TypeError: Error {
    case unexpectedEndOfString
    case invalidCharacter(Character)
    case unbalancedBrackets
    case invalidArraySyntax
    case invalidBitfieldSyntax
    case invalidStructUnionName
}


class TypeDecoder {

    private var scanner: Scanner!

    /// Parses a full Objective-C method type encoding string.
    func decodeMethodEncoding(_ encoding: String) throws -> DecodedMethodSignature {
        self.scanner = Scanner(string: encoding)
        scanner.charactersToBeSkipped = nil

        let returnType = try decodeSingleTypeAndSkipQualifiersAndOffsets()

        var arguments: [DecodedType] = []
        while !scanner.isAtEnd {
             arguments.append(try decodeSingleTypeAndSkipQualifiersAndOffsets())
        }

        return DecodedMethodSignature(returnType: returnType, arguments: arguments)
    }

    /// Parses a single type encoding unit.
    func decodeType(_ encoding: String) throws -> DecodedType {
        self.scanner = Scanner(string: encoding)
        scanner.charactersToBeSkipped = nil
        let type = try decodeSingleType()
        guard scanner.isAtEnd else {
            let errorChar = scanner.string[scanner.currentIndex]
            throw TypeError.invalidCharacter(errorChar)
        }
        return type
    }

    // MARK: - Internal Parsing Logic

    private func skipQualifiers() {
        let qualifiers = CharacterSet(charactersIn: "rnNoORVA")
        _ = scanner.scanCharacters(from: qualifiers)
    }

    private func skipOffsets() {
        _ = scanner.scanCharacters(from: .decimalDigits)
    }

     private func decodeSingleTypeAndSkipQualifiersAndOffsets() throws -> DecodedType {
         skipQualifiers()
         let type = try decodeSingleType()
         skipOffsets()
         return type
     }


    private func decodeSingleType() throws -> DecodedType {
        guard !scanner.isAtEnd else {
             throw TypeError.unexpectedEndOfString
         }
        let char = scanner.string[scanner.currentIndex]
        scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)

        // FIX: Switch on String(char) and use double quotes for cases
        //      to workaround potential compiler/linter issues with character literals.
        switch String(char) {
        // Basic Types
        case "c": return .char
        case "C": return .uchar
        case "s": return .short
        case "S": return .ushort
        case "i": return .int
        case "I": return .uint
        case "l": return .long
        case "L": return .ulong
        case "q": return .longlong
        case "Q": return .ulonglong
        case "f": return .float
        case "d": return .double
        case "B": return .bool
        case "v": return .void
        case "*": return .cString

        // ObjC Specific
        case "@": return try decodeObjectType()
        case "#": return .class(name: nil)
        case ":": return .selector

        // Modifiers / Complex Types
        case "^": return try decodePointerType()
        case "[": return try decodeArrayType()
        case "{": return try decodeStructOrUnionType(open: "{", close: "}", isStruct: true) // Use Character here
        case "(": return try decodeStructOrUnionType(open: "(", close: ")", isStruct: false) // Use Character here
        case "b": return try decodeBitfieldType()
        case "?": return .unknown(encoding: String(char)) // Keep '?' handling basic

        default:
            // Rewind scanner if we advanced for an unknown character
            scanner.currentIndex = scanner.string.index(before: scanner.currentIndex)
            return .unknown(encoding: String(char))
        }
    }

    // The rest of the decoding methods (decodeObjectType, decodePointerType, etc.)
    // remain the same as the previous corrected version...

    private func decodeObjectType() throws -> DecodedType {
        if scanner.scanString("\"") != nil {
             if scanner.scanString("<") != nil {
                 // Simple block skipping for now
                 var level = 1
                 while level > 0 {
                     guard !scanner.isAtEnd else { throw TypeError.unbalancedBrackets }
                     if scanner.scanString("<") != nil { level += 1 }
                     else if scanner.scanString(">") != nil { level -= 1}
                     else { scanner.currentIndex = scanner.string.index(after: scanner.currentIndex) } // Advance
                 }
                 _ = scanner.scanString("?") // Optional '?' after block encoding
                 return .block
             } else {
                 let name = scanner.scanUpToString("\"")
                 guard scanner.scanString("\"") != nil else { throw TypeError.unbalancedBrackets }
                 return .object(name: name ?? "<ErrorName>")
             }
        } else if scanner.scanString("?") != nil {
             return .block
        } else {
            return .class(name: nil) // 'id'
        }
    }

    private func decodePointerType() throws -> DecodedType {
         let pointeeType = try decodeSingleType()
         return .pointer(pointee: pointeeType)
    }

    private func decodeArrayType() throws -> DecodedType {
            guard let countStr = scanner.scanCharacters(from: .decimalDigits), let count = Int(countStr) else {
                throw TypeError.invalidArraySyntax
            }
            let elementType = try decodeSingleType()
            guard scanner.scanString("]") != nil else {
                throw TypeError.invalidArraySyntax
            }
            // FIX: Use the parsed 'count' variable
            return .array(count: count, elementType: elementType)
        }

    private func decodeStructOrUnionType(open: Character, close: Character, isStruct: Bool) throws -> DecodedType {
        let name = scanner.scanUpToString("=") ?? ""

        if scanner.scanString("=") == nil {
            guard scanner.scanUpToString(String(close)) != nil || !name.isEmpty else {
                 if scanner.scanString(String(close)) != nil {
                    return isStruct ? .struct(name: "", members: []) : .union(name: "", members: [])
                 } else {
                     throw TypeError.unbalancedBrackets
                 }
            }
             guard scanner.scanString(String(close)) != nil else { throw TypeError.unbalancedBrackets }
             return isStruct ? .struct(name: name, members: nil) : .union(name: name, members: nil)
        }

        var members: [(String?, DecodedType)] = []
        while scanner.scanString(String(close)) == nil {
             if scanner.isAtEnd { throw TypeError.unbalancedBrackets }
             let memberType = try decodeSingleType()
             members.append((nil, memberType))
        }
        return isStruct ? DecodedType.struct(name: name, members: members) : DecodedType.union(name: name, members: members)
    }


     private func decodeBitfieldType() throws -> DecodedType {
         guard let sizeStr = scanner.scanCharacters(from: .decimalDigits), let size = Int(sizeStr) else {
             throw TypeError.invalidBitfieldSyntax
         }
         return .bitfield(size: size)
     }
}

// DecodedType extension with toObjCString remains the same...
extension DecodedType {
    func toObjCString(typeNamer: ((String) -> String?)? = nil) -> String {
        switch self {
        case .class: return "id"
        case .object(let name): return "\(typeNamer?(name) ?? name) *"
        case .block: return "void (^)(void)"
        case .selector: return "SEL"
        case .char: return "char"
        case .uchar: return "unsigned char"
        case .short: return "short"
        case .ushort: return "unsigned short"
        case .int: return "int"
        case .uint: return "unsigned int"
        case .long: return "long"
        case .ulong: return "unsigned long"
        case .longlong: return "long long"
        case .ulonglong: return "unsigned long long"
        case .float: return "float"
        case .double: return "double"
        case .bool: return "BOOL"
        case .void: return "void"
        case .cString: return "char *"
        case .pointer(let pointee):
            let pointeeStr = pointee?.toObjCString(typeNamer: typeNamer) ?? "void"
            if pointeeStr == "char *" { return "char **" }
            if pointeeStr == "void" { return "void *" }
            if pointeeStr.hasSuffix("*") || pointeeStr == "id" || pointeeStr == "SEL" || pointeeStr == "Class" {
                 return "\(pointeeStr) *"
            } else {
                 return "\(pointeeStr) *"
            }
        case .struct(let name, _):
            let mappedName = typeNamer?(name) ?? name
            return mappedName.isEmpty ? "struct <anonymous>" : "struct \(mappedName)"
        case .union(let name, _):
            let mappedName = typeNamer?(name) ?? name
            return mappedName.isEmpty ? "union <anonymous>" : "union \(mappedName)"
        case .array(let count, let elementType):
             let elementStr = elementType.toObjCString(typeNamer: typeNamer)
             return "\(elementStr) *"
        case .unknown(let encoding): return "/*?\(encoding)?*/"
        case .bitfield(let size): return "unsigned int /* bitfield :\(size) */"
        }
    }
}
