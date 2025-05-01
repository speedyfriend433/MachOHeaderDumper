//
//  File.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation

// MARK: - Data Reading Extension

extension UnsafeRawBufferPointer {
    /// Reads a structure or value of type T at a specific file offset relative to the start of this buffer.
    /// Assumes native byte order. For non-native, byte swapping must be applied to the result.
    func read<T>(at bufferOffset: Int) throws -> T {
        let requiredSize = MemoryLayout<T>.size
        let endOffset = bufferOffset + requiredSize

        // Ensure the read is within the bounds of *this specific buffer pointer*
        guard bufferOffset >= 0, endOffset <= self.count else {
            throw MachOParseError.dataReadOutOfBounds(offset: bufferOffset, length: requiredSize, totalSize: self.count)
        }
        guard let baseAddress = self.baseAddress else {
            // This should generally not happen for a valid buffer pointer
            throw MachOParseError.dataReadOutOfBounds(offset: bufferOffset, length: requiredSize, totalSize: self.count)
        }
        return baseAddress.advanced(by: bufferOffset).load(as: T.self)
    }

    /// Reads a null-terminated C string starting at a specific file offset relative to the start of this buffer.
    func readCString(at bufferOffset: Int) throws -> String {
        guard bufferOffset >= 0, bufferOffset < self.count else {
            // Use UInt64 for the error to match previous API, though offset is Int here
            throw MachOParseError.stringReadOutOfBounds(offset: UInt64(bufferOffset))
        }
        guard let baseAddress = self.baseAddress else {
            throw MachOParseError.stringReadOutOfBounds(offset: UInt64(bufferOffset))
        }

        let pointer = baseAddress.advanced(by: bufferOffset).assumingMemoryBound(to: CChar.self)

        // Safely determine the length within the buffer's bounds
        var length = 0
        while bufferOffset + length < self.count && pointer[length] != 0 {
            length += 1
        }

        // Check if null terminator was found within bounds
        guard bufferOffset + length < self.count else {
             throw MachOParseError.invalidCString(offset: UInt64(bufferOffset)) // Unterminated within buffer
        }

        return String(cString: pointer)
    }

    /// Creates a new buffer pointer representing a slice of this buffer.
     func slice(offset: Int, length: Int) throws -> UnsafeRawBufferPointer {
         let endOffset = offset + length
         guard offset >= 0, length >= 0, endOffset <= self.count else {
             throw MachOParseError.dataReadOutOfBounds(offset: offset, length: length, totalSize: self.count)
         }
         // Use rebasing initializer which is safer as it doesn't rely on baseAddress + offset calculation
         return UnsafeRawBufferPointer(rebasing: self[offset..<endOffset])
     }
}
