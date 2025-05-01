//
//  DyldInfoParser.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: DyldInfoParser.swift (Complete and Corrected)

import Foundation

enum DyldInfoParseError: Error, LocalizedError, Equatable {
    case invalidOpcode(UInt8)
    case ulebDecodeError(offset: Int)
    case slebDecodeError(offset: Int)
    case bufferReadError(offset: Int)
    case stringReadError(offset: Int)
    case missingDyldInfoCommand
    case invalidOffsetOrSize(name: String)
    case trieWalkOutOfBounds(offset: Int)
    case invalidExportInfo(offset: Int)
    case invalidReExportString(offset: Int)

    var errorDescription: String? {
        switch self {
        case .invalidOpcode(let op): return "Invalid dyld opcode: 0x\(String(op, radix: 16))"
        case .ulebDecodeError(let offset): return "Error decoding ULEB128 at offset \(offset)"
        case .slebDecodeError(let offset): return "Error decoding SLEB128 at offset \(offset)"
        case .bufferReadError(let offset): return "Error reading buffer at offset \(offset)"
        case .stringReadError(let offset): return "Error reading C string at offset \(offset)"
        case .missingDyldInfoCommand: return "LC_DYLD_INFO_ONLY command not found"
        case .invalidOffsetOrSize(let name): return "Invalid offset/size for \(name) data"
        case .trieWalkOutOfBounds(let offset): return "Export trie walk went out of bounds at offset \(offset)"
        case .invalidExportInfo(let offset): return "Invalid export info data found at offset \(offset)"
        case .invalidReExportString(let offset): return "Invalid re-export string found at offset \(offset)"
        }
    }

    // Equatable conformance (synthesized or manual if needed)
     static func == (lhs: DyldInfoParseError, rhs: DyldInfoParseError) -> Bool {
         // Basic comparison for now, can be refined
         return lhs.localizedDescription == rhs.localizedDescription
     }
}

class DyldInfoParser {

    private let dataRegion: UnsafeRawBufferPointer // Full Mach-O data slice region
    private let dyldInfoCmd: dyld_info_command   // The LC_DYLD_INFO command struct
    private var exportRegionCache: UnsafeRawBufferPointer? = nil // Cache the export data slice

    init(parsedData: ParsedMachOData) throws {
        guard let dyldCmd = parsedData.loadCommands.compactMap({
            if case .dyldInfo(let cmd) = $0 { return cmd } else { return nil }
        }).first else {
             throw DyldInfoParseError.missingDyldInfoCommand
        }
        self.dyldInfoCmd = dyldCmd
        self.dataRegion = parsedData.dataRegion
    }

    func parseAll() throws -> ParsedDyldInfo {
        var info = ParsedDyldInfo()

        info.rebases = try parseRebases()
        info.binds = try parseBinds(offset: dyldInfoCmd.bind_off, size: dyldInfoCmd.bind_size)
        info.weakBinds = try parseBinds(offset: dyldInfoCmd.weak_bind_off, size: dyldInfoCmd.weak_bind_size)
        info.lazyBinds = try parseBinds(offset: dyldInfoCmd.lazy_bind_off, size: dyldInfoCmd.lazy_bind_size)
        info.exports = try parseExports()

        return info
    }

    // MARK: - Rebase Parsing

    private func parseRebases() throws -> [RebaseOperation] {
        guard dyldInfoCmd.rebase_size > 0 else { return [] }
        let offset = Int(dyldInfoCmd.rebase_off)
        let size = Int(dyldInfoCmd.rebase_size)
        guard offset >= 0, size > 0, offset + size <= dataRegion.count else {
            throw DyldInfoParseError.invalidOffsetOrSize(name: "rebase")
        }

        let rebaseRegion = try dataRegion.slice(offset: offset, length: size)
        var rebases: [RebaseOperation] = []
        var reader = OpcodeReader(region: rebaseRegion) // Pass the SLICED region

        var currentSegmentIndex: Int = 0
        var currentSegmentOffset: UInt64 = 0
        var currentType: UInt8 = UInt8(REBASE_TYPE_POINTER)
        let pointerSize = UInt64(POINTER_SIZE)

        while !reader.isAtEnd {
            let opcodeByte = try reader.readByte()
            let opcode = opcodeByte & REBASE_OPCODE_MASK
            let immediate = opcodeByte & REBASE_IMMEDIATE_MASK

            switch opcode {
            case REBASE_OPCODE_DONE:
                return rebases

            case REBASE_OPCODE_SET_TYPE_IMM:
                currentType = immediate

            case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
                currentSegmentIndex = Int(immediate)
                currentSegmentOffset = try reader.readULEB128()

            case REBASE_OPCODE_ADD_ADDR_ULEB:
                currentSegmentOffset = currentSegmentOffset &+ (try reader.readULEB128())

            case REBASE_OPCODE_ADD_ADDR_IMM_SCALED:
                currentSegmentOffset = currentSegmentOffset &+ (UInt64(immediate) * pointerSize)

            case REBASE_OPCODE_DO_REBASE_IMM_TIMES:
                for _ in 0..<Int(immediate) {
                    rebases.append(RebaseOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType))
                    currentSegmentOffset = currentSegmentOffset &+ pointerSize
                }

            case REBASE_OPCODE_DO_REBASE_ULEB_TIMES:
                let count = try reader.readULEB128()
                for _ in 0..<count {
                   rebases.append(RebaseOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType))
                   currentSegmentOffset = currentSegmentOffset &+ pointerSize
                }

            case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB:
                rebases.append(RebaseOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType))
                let ulebValue = try reader.readULEB128()
                currentSegmentOffset = currentSegmentOffset &+ ulebValue
                currentSegmentOffset = currentSegmentOffset &+ pointerSize

            case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB:
                let count = try reader.readULEB128()
                let skip = try reader.readULEB128()
                let increment = skip &+ pointerSize
                for _ in 0..<count {
                    rebases.append(RebaseOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType))
                    currentSegmentOffset = currentSegmentOffset &+ increment
                }

            default:
                throw DyldInfoParseError.invalidOpcode(opcodeByte)
            }
        }
        // Should have returned via DONE, but if loop finishes, return what we have
        print("Warning: Reached end of rebase region without DONE opcode.")
        return rebases
    }

    // MARK: - Bind Parsing (Generic for Normal, Weak, Lazy)

    private func parseBinds(offset: UInt32, size: UInt32) throws -> [BindOperation] {
        guard size > 0 else { return [] }
        let startOffset = Int(offset)
        let dataSize = Int(size)
        guard startOffset >= 0, dataSize > 0, startOffset + dataSize <= dataRegion.count else {
             throw DyldInfoParseError.invalidOffsetOrSize(name: "bind (\(offset),\(size))")
        }

        let bindRegion = try dataRegion.slice(offset: startOffset, length: dataSize)
        var binds: [BindOperation] = []
        var reader = OpcodeReader(region: bindRegion) // Pass the SLICED region

        var currentSegmentIndex: Int = 0
        var currentSegmentOffset: UInt64 = 0
        var currentType: UInt8 = UInt8(BIND_TYPE_POINTER)
        var currentDylibOrdinal: Int = 0
        var currentSymbolName: String = ""
        var currentSymbolFlags: UInt8 = 0
        var currentAddend: Int64 = 0 // SLEB128
        let pointerSize = UInt64(POINTER_SIZE)

        while !reader.isAtEnd {
            let opcodeByte = try reader.readByte()
            let opcode = opcodeByte & BIND_OPCODE_MASK
            let immediate = opcodeByte & BIND_IMMEDIATE_MASK

            switch opcode {
            case BIND_OPCODE_DONE:
                return binds

            case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
                currentDylibOrdinal = Int(immediate)

            case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
                currentDylibOrdinal = Int(try reader.readULEB128())

            case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
                if immediate == 0 {
                    currentDylibOrdinal = BIND_SPECIAL_DYLIB_SELF
                } else {
                    // Sign extend the immediate value
                    currentDylibOrdinal = Int(Int8(bitPattern: BIND_OPCODE_SET_DYLIB_SPECIAL_IMM | immediate))
                }

            case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
                currentSymbolFlags = immediate
                currentSymbolName = try reader.readCString()

            case BIND_OPCODE_SET_TYPE_IMM:
                currentType = immediate

            case BIND_OPCODE_SET_ADDEND_SLEB:
                currentAddend = try reader.readSLEB128()

            case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
                currentSegmentIndex = Int(immediate)
                currentSegmentOffset = try reader.readULEB128()

            case BIND_OPCODE_ADD_ADDR_ULEB:
                currentSegmentOffset = currentSegmentOffset &+ (try reader.readULEB128())

            case BIND_OPCODE_DO_BIND:
                binds.append(BindOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType, flags: currentSymbolFlags, addend: currentAddend, dylibOrdinal: currentDylibOrdinal, symbolName: currentSymbolName))
                currentSegmentOffset = currentSegmentOffset &+ pointerSize

            case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
                binds.append(BindOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType, flags: currentSymbolFlags, addend: currentAddend, dylibOrdinal: currentDylibOrdinal, symbolName: currentSymbolName))
                let ulebValue = try reader.readULEB128()
                currentSegmentOffset = currentSegmentOffset &+ ulebValue
                currentSegmentOffset = currentSegmentOffset &+ pointerSize

            case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
                binds.append(BindOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType, flags: currentSymbolFlags, addend: currentAddend, dylibOrdinal: currentDylibOrdinal, symbolName: currentSymbolName))
                let immValue = UInt64(immediate) * pointerSize
                currentSegmentOffset = currentSegmentOffset &+ immValue
                currentSegmentOffset = currentSegmentOffset &+ pointerSize

            case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB:
                let count = try reader.readULEB128()
                let skip = try reader.readULEB128()
                let increment = skip &+ pointerSize
                for _ in 0..<count {
                    binds.append(BindOperation(segmentIndex: currentSegmentIndex, segmentOffset: currentSegmentOffset, type: currentType, flags: currentSymbolFlags, addend: currentAddend, dylibOrdinal: currentDylibOrdinal, symbolName: currentSymbolName))
                    currentSegmentOffset = currentSegmentOffset &+ increment
                }

            // BIND_OPCODE_THREADED (0xD0) - handle if needed, often involves thread-local bindings
            // case BIND_OPCODE_THREADED:
            //    print("Warning: BIND_OPCODE_THREADED encountered - not fully handled.")
            //    // Might need specific logic depending on subcommand
            //    break

            default:
                throw DyldInfoParseError.invalidOpcode(opcodeByte)
            }
        }
        print("Warning: Reached end of bind region without DONE opcode.")
        return binds
    }

    // MARK: - Export Trie Parsing

    private func parseExports() throws -> [ExportedSymbol] {
        guard dyldInfoCmd.export_size > 0 else { return [] }
        let offset = Int(dyldInfoCmd.export_off)
        let size = Int(dyldInfoCmd.export_size)
        guard offset >= 0, size > 0, offset + size <= dataRegion.count else {
            throw DyldInfoParseError.invalidOffsetOrSize(name: "export")
        }

        // Use instance variable cache
        if exportRegionCache == nil {
             exportRegionCache = try dataRegion.slice(offset: offset, length: size)
        }
        // Ensure cache is valid (should be unless slice failed, which throws)
        guard let exportRegion = exportRegionCache else {
             throw DyldInfoParseError.invalidOffsetOrSize(name: "export cache")
        }

        var exports: [ExportedSymbol] = [] // Change to instance variable if preferred
        // Start walking from offset 0 within the *exportRegion slice*
        try walkExportTrie(region: exportRegion, currentOffset: 0, currentPrefix: "", results: &exports)

        return exports
    }

    /// Recursively walks the export trie. Pass the sliced export region.
    private func walkExportTrie(region: UnsafeRawBufferPointer, currentOffset: Int, currentPrefix: String, results: inout [ExportedSymbol]) throws {
        guard currentOffset < region.count else {
            throw DyldInfoParseError.trieWalkOutOfBounds(offset: currentOffset)
        }

        // Use a local reader starting at the correct offset *within the slice*
        var reader = OpcodeReader(region: region, startOffset: currentOffset)
        let nodeStartOffset = reader.offset // Remember start for error reporting

        // 1. Read terminal size
        let terminalSize = try reader.readULEB128()
        let endOfTerminalInfoOffset = reader.offset + Int(terminalSize)

        guard endOfTerminalInfoOffset <= region.count else {
             throw DyldInfoParseError.invalidExportInfo(offset: nodeStartOffset)
        }

        // 2. Parse export info if terminal size > 0
        if terminalSize > 0 {
            // Keep track of bytes read within terminal info for validation
            let terminalInfoStartOffset = reader.offset

            let flags = try reader.readULEB128()
            var address: UInt64 = 0
            var otherOffset: UInt64? = nil
            var importName: String? = nil
            var importOrdinal: Int? = nil

            if (flags & EXPORT_SYMBOL_FLAGS_REEXPORT) != 0 {
                importOrdinal = Int(try reader.readULEB128())
                if reader.offset < endOfTerminalInfoOffset {
                     // Read CString *only* if within terminal size bounds
                     importName = try reader.readCString() // Can throw if no null terminator within bounds
                     if importName?.isEmpty == true { importName = nil }
                } else if reader.offset == endOfTerminalInfoOffset {
                     // Re-export with same name, no string present
                     importName = nil
                } else {
                     // Should not happen if initial bound check passed
                     throw DyldInfoParseError.invalidReExportString(offset: reader.offset)
                }
            } else {
                address = try reader.readULEB128()
                if (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER) != 0 {
                    if reader.offset < endOfTerminalInfoOffset {
                         otherOffset = try reader.readULEB128()
                    } else {
                         print("Warning: Expected resolver offset missing for stub export '\(currentPrefix)' at offset \(nodeStartOffset)")
                         // Allow continuing, otherOffset remains nil
                    }
                }
            }

            // Validate that we didn't read past the declared terminal size
            guard reader.offset <= endOfTerminalInfoOffset else {
                print("Warning: Read past terminal size (\(terminalSize)) for export '\(currentPrefix)' at offset \(nodeStartOffset)")
                // Skip this entry as it's likely corrupt
                reader.offset = endOfTerminalInfoOffset // Try to recover reader position
                // Continue to children parsing below
                return
            }

            // If we read less than terminal size, advance reader past padding
            if reader.offset < endOfTerminalInfoOffset {
                reader.offset = endOfTerminalInfoOffset
            }

            // Add the valid export record if we didn't skip due to error
            results.append(ExportedSymbol(
                name: currentPrefix,
                flags: flags,
                address: address,
                otherOffset: otherOffset,
                importName: importName,
                importLibraryOrdinal: importOrdinal
            ))
        }
        // else: No symbol ends at this node, reader.offset is already past terminal size (0)

        // 3. Read children count (make sure reader is at correct position)
        guard !reader.isAtEnd else { return }
        let childrenCount = try reader.readByte()

        // 4. Iterate through children
        for _ in 0..<childrenCount {
            guard !reader.isAtEnd else {
                 throw DyldInfoParseError.trieWalkOutOfBounds(offset: reader.offset)
            }
            let edgeString = try reader.readCString() // Reads edge label

            guard !reader.isAtEnd else {
                 throw DyldInfoParseError.trieWalkOutOfBounds(offset: reader.offset)
            }
            let childNodeRelativeOffset = try reader.readULEB128() // Offset from start of export region
            let childNodeAbsoluteOffset = Int(childNodeRelativeOffset)

            // Recursive call - use the same 'region' (the export slice)
            try walkExportTrie(
                region: region,
                currentOffset: childNodeAbsoluteOffset, // Pass absolute offset *within the slice*
                currentPrefix: currentPrefix + edgeString,
                results: &results
            )
        }
    }
}


// MARK: - Opcode Stream Reader Helper

private struct OpcodeReader {
    let region: UnsafeRawBufferPointer
    var offset: Int // Current position within the region

    init(region: UnsafeRawBufferPointer, startOffset: Int = 0) {
        self.region = region
        self.offset = max(0, min(startOffset, region.count))
    }

    var isAtEnd: Bool { offset >= region.count }

    mutating func readByte() throws -> UInt8 {
        guard offset < region.count else { throw DyldInfoParseError.bufferReadError(offset: offset) }
        let byte = region[offset]
        offset += 1
        return byte
    }

    mutating func readULEB128() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt = 0
        var byte: UInt8
        let initialOffset = offset // For error reporting

        repeat {
            guard !isAtEnd else { throw DyldInfoParseError.ulebDecodeError(offset: initialOffset) } // Check before reading
            byte = try readByte() // Advances offset
            let slice = UInt64(byte & 0x7F)

            if shift >= 64 || ((slice << shift) >> shift) != slice {
                throw DyldInfoParseError.ulebDecodeError(offset: initialOffset)
            }
            result = result &+ (slice << shift) // Use overflow addition for result? Should not overflow usually.
            shift += 7
        } while (byte & 0x80) != 0

        return result
    }

    mutating func readSLEB128() throws -> Int64 {
         var result: Int64 = 0
         var shift: UInt = 0
         var byte: UInt8
         let size: UInt = 64
         let initialOffset = offset // For error reporting

         repeat {
             guard !isAtEnd else { throw DyldInfoParseError.slebDecodeError(offset: initialOffset) }
             byte = try readByte()
             let slice = Int64(byte & 0x7F)

             if shift >= size || ((slice << shift) >> shift) != slice {
                  throw DyldInfoParseError.slebDecodeError(offset: initialOffset)
             }
             result = result &+ (slice << shift) // Use overflow addition? Less likely needed here.
             shift += 7
         } while (byte & 0x80) != 0

         if (shift < size) && (byte & 0x40) != 0 {
             result |= -(Int64(1) << shift)
         }

         return result
     }

     mutating func readCString() throws -> String {
         let startOffset = offset
         while offset < region.count {
             if region[offset] == 0 {
                 let stringData = region[startOffset..<offset]
                 offset += 1
                 // Use lossy conversion as fallback? Or throw?
                 return String(data: Data(stringData), encoding: .utf8) ?? "<Invalid UTF8 Str@\(startOffset)>"
             }
             offset += 1
         }
         // If loop finishes without finding null terminator within the region
         throw DyldInfoParseError.stringReadError(offset: startOffset)
     }
}
