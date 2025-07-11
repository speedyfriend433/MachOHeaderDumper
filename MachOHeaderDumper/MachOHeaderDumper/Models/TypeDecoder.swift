import Foundation

// MARK: - Type Representation

indirect enum DecodedType {
    case `class`(name: String?, protocols: [String])
    case object(name: String, protocols: [String])
    case block
    case selector
    case char, uchar, short, ushort, int, uint, long, ulong, longlong, ulonglong
    case float, double, bool, void
    case cString
    case pointer(pointee: DecodedType?)
    case `struct`(name: String, members: [(String?, DecodedType)]?)
    case union(name: String, members: [(String?, DecodedType)]?)
    case array(count: Int, elementType: DecodedType)
    case bitfield(size: Int)
    case unknown(encoding: String)

    func withProtocols(_ newProtocols: [String]) -> DecodedType {
        switch self {
        case .class(let name, let existing):
            return .class(name: name, protocols: existing + newProtocols)
        case .object(let name, let existing):
            return .object(name: name, protocols: existing + newProtocols)
        default:
            return self
        }
    }
    
    func isId() -> Bool {
        if case .class(let name, _) = self {
            return name == nil
        }
        return false
    }
}

struct DecodedMethodSignature {
    let returnType: DecodedType
    let arguments: [DecodedType] // First arg is often self (@), second is _cmd (:)
}

enum TypeError: Error {
    case unexpectedEndOfString
    case invalidCharacter(Character)
    case unbalancedBrackets
    case invalidArraySyntax
    case invalidBitfieldSyntax
}

// MARK: - Decoder Class

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

    /// Parses a single type encoding unit (e.g., "i", "^{MyStruct=ic}").
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
        guard !scanner.isAtEnd else { throw TypeError.unexpectedEndOfString }
        let char = scanner.string[scanner.currentIndex]
        scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)

        switch String(char) {
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
        case "@": return try decodeObjectType()
        case "#": return .class(name: "Class", protocols: [])
        case ":": return .selector
        case "^": return try decodePointerType()
        case "[": return try decodeArrayType()
        case "{": return try decodeStructOrUnionType(open: "{", close: "}", isStruct: true)
        case "(": return try decodeStructOrUnionType(open: "(", close: ")", isStruct: false)
        case "b": return try decodeBitfieldType()
        case "?": return .block

        default:
            scanner.currentIndex = scanner.string.index(before: scanner.currentIndex)
            return .unknown(encoding: String(char))
        }
    }

    /// ENHANCED to handle protocol conformances like @"<FLEXMirror>" or @"ClassName<Proto1,Proto2>"
    private func decodeObjectType() throws -> DecodedType {
        if scanner.scanString("\"") == nil {
            if scanner.scanString("?") != nil { return .block }
            return .class(name: nil, protocols: []) // id
        }

        let className = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "<\""))

        var objectType: DecodedType
        if let name = className, !name.isEmpty {
            objectType = .object(name: name, protocols: [])
        } else {
            objectType = .class(name: nil, protocols: [])
        }

        if scanner.scanString("<") != nil {
            if className?.isEmpty ?? true {
                 var level = 1
                 while level > 0 {
                     guard !scanner.isAtEnd else { throw TypeError.unbalancedBrackets }
                     if scanner.scanString("<") != nil { level += 1 }
                     else if scanner.scanString(">") != nil { level -= 1}
                     else { scanner.currentIndex = scanner.string.index(after: scanner.currentIndex) }
                 }
                 _ = scanner.scanString("\"")
                 return .block
            }
            
            var protocols: [String] = []
            while scanner.scanString(">") == nil {
                 if scanner.isAtEnd { throw TypeError.unbalancedBrackets }
                 if let protoName = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: ",>")) {
                      if !protoName.isEmpty { protocols.append(protoName) }
                 }
                 _ = scanner.scanString(",")
            }
            objectType = objectType.withProtocols(protocols)
        }

        guard scanner.scanString("\"") != nil else {
            print("Warning: TypeDecoder: Missing closing quote in object type encoding.")
            return objectType
        }

        return objectType
    }

    private func decodePointerType() throws -> DecodedType {
         let pointeeType = try decodeSingleType()
         return .pointer(pointee: pointeeType)
    }

    private func decodeArrayType() throws -> DecodedType {
        guard let countStr = scanner.scanCharacters(from: .decimalDigits), let count = Int(countStr) else { throw TypeError.invalidArraySyntax }
        let elementType = try decodeSingleType()
        guard scanner.scanString("]") != nil else { throw TypeError.invalidArraySyntax }
        return .array(count: count, elementType: elementType)
    }

    private func decodeStructOrUnionType(open: Character, close: Character, isStruct: Bool) throws -> DecodedType {
        let name = scanner.scanUpToString("=") ?? ""
        if scanner.scanString("=") == nil {
            _ = scanner.scanUpToString(String(close))
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
         guard let sizeStr = scanner.scanCharacters(from: .decimalDigits), let size = Int(sizeStr) else { throw TypeError.invalidBitfieldSyntax }
         return .bitfield(size: size)
     }
}

// MARK: - String Formatting Extension

extension DecodedType {
    /// Converts the decoded type into a human-readable Objective-C string representation.
    func toObjCString(typeNamer: ((String) -> String?)? = nil) -> String {
        switch self {
        case .class(let name, let protocols):
            let base = name ?? "id"
            if protocols.isEmpty {
                return base
            } else {
                return "\(base) <\(protocols.joined(separator: ", "))>"
            }
        case .object(let name, let protocols):
            let mappedName = typeNamer?(name) ?? name
            if protocols.isEmpty {
                return "\(mappedName) *"
            } else {
                 return "\(mappedName) <\(protocols.joined(separator: ", "))> *"
            }
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
            // If pointee is already an object pointer (id<...>, ClassName *), don't add a second pointer
            if pointeeStr.hasSuffix("*") || pointeeStr.contains("<") {
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
        case .array(_, let elementType):
             let elementStr = elementType.toObjCString(typeNamer: typeNamer)
             return "\(elementStr) *" 
        case .unknown(let encoding): return "/*?\(encoding)?*/"
        case .bitfield(let size): return "unsigned int /* bitfield :\(size) */"
        }
    }
}
