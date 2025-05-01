//
//  FunctionStartsParser.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Utils/FunctionStartsParser.swift (Corrected Error Handling)

import Foundation

// --- Define error enum HERE or ensure global access ---
enum FunctionStartsParseError: Error, LocalizedError, Equatable { // Make Equatable if needed
    case commandNotFound
    case invalidLinkeditData
    case ulebDecodeError(offset: Int) // Matches DyldInfoParseError case

    var errorDescription: String? {
        switch self {
        case .commandNotFound: return "LC_FUNCTION_STARTS command not found."
        case .invalidLinkeditData: return "Invalid offset/size for function starts data in __LINKEDIT."
        case .ulebDecodeError(let offset): return "Error decoding ULEB128 delta at offset \(offset)."
        }
    }
    // Add Equatable conformance if comparing these errors later
    static func == (lhs: FunctionStartsParseError, rhs: FunctionStartsParseError) -> Bool {
        switch(lhs, rhs) {
        case (.commandNotFound, .commandNotFound): return true
        case (.invalidLinkeditData, .invalidLinkeditData): return true
        case (.ulebDecodeError(let o1), .ulebDecodeError(let o2)): return o1 == o2
        default: return false
        }
    }
}

class FunctionStartsParser {

    /// Parses the function starts data from the LC_FUNCTION_STARTS command.
    /// - Parameter parsedData: The fully parsed Mach-O data.
    /// - Returns: An array of absolute function start VM addresses.
    /// - Throws: `FunctionStartsParseError` if parsing fails.
    static func parseFunctionStarts(in parsedData: ParsedMachOData) throws -> [UInt64] {
        // 1. Find the LC_FUNCTION_STARTS command
        guard let funcStartsCmdCase = parsedData.loadCommands.first(where: { if case .functionStarts = $0 { return true } else { return false } }), case .functionStarts(let leCmd) = funcStartsCmdCase else { throw FunctionStartsParseError.commandNotFound }

        // 2. Validate the offset and size
        let offset = Int(leCmd.dataoff); let size = Int(leCmd.datasize)
                guard offset >= 0, size > 0, offset + size <= parsedData.dataRegion.count else { throw FunctionStartsParseError.invalidLinkeditData }

        print("FunctionStartsParser: Found LC_FUNCTION_STARTS at offset \(offset), size \(size).")

        // 3. Get the data slice (this data is usually in __LINKEDIT, but dataoff is absolute file offset)
        let funcStartsRegion = try parsedData.dataRegion.slice(offset: offset, length: size)
        var reader = OpcodeReader(region: funcStartsRegion) // Use the same ULEB reader helper

        // 4. Decode ULEB128 deltas relative to the image base address
        var addresses: [UInt64] = []
        var currentAddress = parsedData.baseAddress // Start at the image base

        while !reader.isAtEnd {
            do {
                let delta = try reader.readULEB128()
                if delta == 0 { // Zero delta signifies the end (usually) or padding? Let's stop.
                    // Although specification says it continues until datasize is consumed.
                    // Let's trust the size primarily. If reader hits end, loop terminates.
                    print("FunctionStartsParser: Encountered zero delta at offset \(reader.offset - 1), continuing until end of data.")
                    // If delta is 0 but we aren't at the end, it implies the function is at currentAddress
                    // Add it *if* this isn't the very first delta (where currentAddress is just baseAddress)
                     if !addresses.isEmpty {
                         // Should we add currentAddress if delta is 0? Ambiguous.
                         // Let's assume delta > 0 means *add* delta to get next address.
                         // If delta == 0, maybe it's padding or error? Skip adding for delta 0.
                     }
                     continue // Skip adding address for delta 0? Or should we add currentAddress? Let's skip.

                }

                // Add the delta to the current address
                currentAddress = currentAddress &+ delta // Use overflow addition
                addresses.append(currentAddress)

                // FIX: Catch the specific DyldInfoParseError.ulebDecodeError case
                            } catch let error as DyldInfoParseError {
                                switch error {
                                case .ulebDecodeError(let ulebOffset):
                                    // Throw the corresponding FunctionStartsParseError with the correct offset
                                    throw FunctionStartsParseError.ulebDecodeError(offset: ulebOffset)
                                case .bufferReadError(let bufOffset):
                                     // Re-throw buffer errors or wrap them
                                     print("FunctionStartsParser: Buffer read error at offset \(bufOffset)")
                                     throw error // Rethrow original for now
                                default:
                                    // Handle other potential DyldInfoParseError cases if OpcodeReader throws them
                                    print("FunctionStartsParser: Unexpected DyldInfoParseError: \(error)")
                                    throw error // Rethrow
                                }
                            } catch {
                                 // Catch other non-DyldInfoParseError types
                                 print("FunctionStartsParser: Unexpected error during ULEB decoding: \(error)")
                                 throw error
                            }
                        }

                        print("FunctionStartsParser: Decoded \(addresses.count) function start addresses.")
                        return addresses
                    }
                }

// Ensure OpcodeReader and DyldInfoParseError are accessible or define needed parts here
// We need OpcodeReader's readULEB128 and the ULEB error case.
// Re-defining minimal OpcodeReader here if needed, or ensure Utils access.
// IMPORTANT: Ensure these definitions match the ones used elsewhere (e.g., DyldInfoParser.swift)
#if !ACCESS_TO_DYLDINFOPARSER // Example conditional compilation
/*enum DyldInfoParseError: Error, Equatable { // Conformance for catch block below
    case ulebDecodeError(offset: Int)
    case bufferReadError(offset: Int)
    // Add other cases if OpcodeReader can throw them
}*/

private struct OpcodeReader {
     let region: UnsafeRawBufferPointer
     var offset: Int = 0
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
         var result: UInt64 = 0; var shift: UInt = 0; var byte: UInt8
         let initialOffset = offset
         repeat {
             guard !isAtEnd else { throw DyldInfoParseError.ulebDecodeError(offset: initialOffset) }
             byte = try readByte()
             let slice = UInt64(byte & 0x7F)
             if shift >= 64 || ((slice << shift) >> shift) != slice { throw DyldInfoParseError.ulebDecodeError(offset: initialOffset) }
             result = result &+ (slice << shift)
             shift += 7
         } while (byte & 0x80) != 0
         return result
     }
}
#endif
