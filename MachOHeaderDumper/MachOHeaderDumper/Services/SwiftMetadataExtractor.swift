//
//  SwiftMetadataExtractor.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//
import Foundation
import MachO
import SwiftDemangle


class SwiftMetadataExtractor {
    private let parsedData: ParsedMachOData
    private let parser: MachOParser

    init(parsedData: ParsedMachOData, parser: MachOParser) {
        self.parsedData = parsedData
        self.parser = parser
    }

    /// Extracts basic Swift type information and demangles names using the bundled library.
    func extract() throws -> ExtractedSwiftMetadata {
        var swiftMeta = ExtractedSwiftMetadata()

        guard let typesSection = findSwiftSection(named: "__swift5_types") else {
            print("ℹ️ SwiftMetadataExtractor: No __swift5_types section found. This is normal for non-Swift binaries.")
            return swiftMeta
        }

        print("ℹ️ SwiftMetadataExtractor: Found __swift5_types section. Processing...")

        let sectionStartVM = typesSection.command.addr
        let sectionStartOffset = UInt64(typesSection.command.offset)
        let sectionSize = Int(typesSection.command.size)
        let pointerSize = RELATIVE_POINTER_SIZE

        var currentOffsetWithinSection: Int = 0
        while currentOffsetWithinSection < sectionSize {
            let relativePointerFileOffset = sectionStartOffset + UInt64(currentOffsetWithinSection)
            let relativePointerVMAddr = sectionStartVM + UInt64(currentOffsetWithinSection)

            guard (relativePointerFileOffset + UInt64(pointerSize)) <= parsedData.dataRegion.count else {
                print("Warning: SwiftMetadataExtractor - Reading Swift type pointer past end of data region.")
                break
            }

            let relativeOffset: Int32 = try parsedData.dataRegion.read(at: Int(relativePointerFileOffset))

            guard let descriptorVMAddr = resolveRelativePointer(baseAddress: relativePointerVMAddr, relativeOffset: relativeOffset) else {
                currentOffsetWithinSection += pointerSize
                continue
            }

            do {
                if var typeInfo = try parseTypeDescriptor(at: descriptorVMAddr) {
                    typeInfo.demangledName = self.demangle(mangledName: typeInfo.mangledName)
                    swiftMeta.types.append(typeInfo)
                }
            } catch {
                 print("Warning: SwiftMetadataExtractor - Skipping descriptor at 0x\(String(descriptorVMAddr, radix: 16)) due to error: \(error)")
            }
            
            currentOffsetWithinSection += pointerSize
        }

        print("ℹ️ SwiftMetadataExtractor: Finished processing __swift5_types. Found \(swiftMeta.types.count) type descriptors.")
        return swiftMeta
    }

    /// Finds a Swift metadata section by name.
    private func findSwiftSection(named sectionName: String) -> ParsedSection? {
        return parsedData.section(segmentName: "__TEXT", sectionName: sectionName)
    }

    /// Parses a Type Context Descriptor at a given VM address.
    private func parseTypeDescriptor(at vmAddress: UInt64) throws -> SwiftTypeInfo? {
        let fileOffset = try parser.fileOffset(for: vmAddress, parsedData: parsedData)

        let flagsOffset = Int(fileOffset)
        let parentRelPtrOffset = flagsOffset + MemoryLayout<UInt32>.size
        let nameRelPtrOffset = parentRelPtrOffset + RELATIVE_POINTER_SIZE

        guard nameRelPtrOffset + RELATIVE_POINTER_SIZE <= parsedData.dataRegion.count else {
             print("Warning: SwiftMetadataExtractor - Descriptor header read out of bounds at VM 0x\(String(vmAddress, radix: 16))")
             return nil
        }

        let flagsValue: UInt32 = try parsedData.dataRegion.read(at: flagsOffset)
        let flags = TypeContextDescriptorFlags(value: flagsValue)
        let kind = flags.kindString
        var mangledName: String = "<\(kind)_NoName>"
        var nameRelOffset: Int32 = 0

        do {
            switch flags.kind {
            case 16:
                guard flagsOffset + MemoryLayout<TargetClassDescriptor>.stride <= parsedData.dataRegion.count else { throw MachOParseError.dataReadOutOfBounds(offset: flagsOffset, length: MemoryLayout<TargetClassDescriptor>.stride, totalSize: parsedData.dataRegion.count) }
                let classDesc: TargetClassDescriptor = try parsedData.dataRegion.read(at: flagsOffset)
                nameRelOffset = classDesc.name
            case 17, 18:
                guard flagsOffset + MemoryLayout<TargetValueTypeDescriptor>.stride <= parsedData.dataRegion.count else { throw MachOParseError.dataReadOutOfBounds(offset: flagsOffset, length: MemoryLayout<TargetValueTypeDescriptor>.stride, totalSize: parsedData.dataRegion.count) }
                let valueDesc: TargetValueTypeDescriptor = try parsedData.dataRegion.read(at: flagsOffset)
                nameRelOffset = valueDesc.name
            default:
                return nil
            }
        } catch let error as MachOParseError where error.isOutOfBoundsError {
             print("Warning: SwiftMetadataExtractor - Reading specific descriptor (kind \(flags.kind)) out of bounds at VM 0x\(String(vmAddress, radix: 16))")
            return nil
        }

        let namePointerAddress = vmAddress + UInt64(nameRelPtrOffset - flagsOffset)
        if let nameVMAddr = resolveRelativePointer(baseAddress: namePointerAddress, relativeOffset: nameRelOffset) {
             do {
                 let nameFileOffset = try parser.fileOffset(for: nameVMAddr, parsedData: parsedData)
                 mangledName = try parsedData.dataRegion.readCString(at: Int(nameFileOffset))
             } catch {
                  mangledName = "<\(kind)_NameReadError>"
             }
        } else if nameRelOffset != 0 {
            mangledName = "<\(kind)_NamePtrResolveError>"
        } else {
            mangledName = "<\(kind)_Anonymous>"
        }

        return SwiftTypeInfo(mangledName: mangledName, demangledName: nil, kind: kind, location: vmAddress)
    }

    /// Demangles a single Swift symbol name using the bundled library.
    // MARK: - Demangling Helper (Uses SwiftDemangle Library String Extension)

        /// Demangles a single Swift symbol name using the bundled library's String extension.
        private func demangle(mangledName: String) -> String {
           do {
               return try mangledName.demangled
           } catch {
               print("Warning: SwiftDemangle library failed for '\(mangledName)': \(error)")
               return mangledName
           }
       }
    }
// extension MachOParseError { var isOutOfBoundsError: Bool...
// func resolveRelativePointer(baseAddress: UInt64, relativeOffset: Int32) -> UInt64?...

// MARK: - Helper Extension for MachOParseError
extension MachOParseError {
    var isOutOfBoundsError: Bool {
        switch self {
        case .dataReadOutOfBounds, .stringReadOutOfBounds:
            return true
        default:
            return false
        }
    }
}

// MARK: - Global Relative Pointer Helper (Ensure defined, maybe in SwiftMetadataStructs.swift)
// func resolveRelativePointer(baseAddress: UInt64, relativeOffset: Int32) -> UInt64?...
