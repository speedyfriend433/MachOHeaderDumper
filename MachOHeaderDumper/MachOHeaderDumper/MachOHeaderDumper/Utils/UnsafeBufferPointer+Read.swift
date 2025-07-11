//
//  File.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation

// MARK: - Data Reading Extension

extension UnsafeRawBufferPointer {
    func read<T>(at bufferOffset: Int) throws -> T {
        let requiredSize = MemoryLayout<T>.size
        let endOffset = bufferOffset + requiredSize

        guard bufferOffset >= 0, endOffset <= self.count else {
            throw MachOParseError.dataReadOutOfBounds(offset: bufferOffset, length: requiredSize, totalSize: self.count)
        }
        guard let baseAddress = self.baseAddress else {
            throw MachOParseError.dataReadOutOfBounds(offset: bufferOffset, length: requiredSize, totalSize: self.count)
        }
        return baseAddress.advanced(by: bufferOffset).load(as: T.self)
    }

    func readCString(at bufferOffset: Int) throws -> String {
        guard bufferOffset >= 0, bufferOffset < self.count else {
            throw MachOParseError.stringReadOutOfBounds(offset: UInt64(bufferOffset))
        }
        guard let baseAddress = self.baseAddress else {
            throw MachOParseError.stringReadOutOfBounds(offset: UInt64(bufferOffset))
        }

        let pointer = baseAddress.advanced(by: bufferOffset).assumingMemoryBound(to: CChar.self)

        var length = 0
        while bufferOffset + length < self.count && pointer[length] != 0 {
            length += 1
        }

        guard bufferOffset + length < self.count else {
             throw MachOParseError.invalidCString(offset: UInt64(bufferOffset))
        }

        return String(cString: pointer)
    }

     func slice(offset: Int, length: Int) throws -> UnsafeRawBufferPointer {
         let endOffset = offset + length
         guard offset >= 0, length >= 0, endOffset <= self.count else {
             throw MachOParseError.dataReadOutOfBounds(offset: offset, length: length, totalSize: self.count)
         }
         return UnsafeRawBufferPointer(rebasing: self[offset..<endOffset])
     }
}
