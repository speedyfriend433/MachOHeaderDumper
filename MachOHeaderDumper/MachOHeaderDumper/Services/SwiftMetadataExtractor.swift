//
//  SwiftMetadataExtractor.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Services/SwiftMetadataExtractor.swift

import Foundation
import MachO // For constants like section names
// Removed Darwin import, as dlsym calls are now in DynamicSymbolLookup

// Assume SwiftMetadataStructs.swift and SwiftModels.swift are defined elsewhere
// Assume Utils/DynamicSymbolLookup.swift is defined elsewhere

class SwiftMetadataExtractor {
    private let parsedData: ParsedMachOData
    private let parser: MachOParser
    // No dlopen handle cache needed here anymore

    // Define the C function signature for _swift_demangle accessible within this file
    // Or make it public/internal in a shared location if needed elsewhere.
    typealias SwiftDemangleFunc = @convention(c) (
        UnsafePointer<CChar>, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
    ) -> UnsafeMutablePointer<CChar>?

    // Store the function pointer, looked up during init
    private let swiftDemangleFunction: DynamicSymbolLookup.SwiftDemangleFunc? // Use typealias from Lookup class

    // FIX: Modify init to accept the function pointer
        init(parsedData: ParsedMachOData,
             parser: MachOParser,
             demanglerFunc: DynamicSymbolLookup.SwiftDemangleFunc?) { // Accept optional pointer
            self.parsedData = parsedData
            self.parser = parser
            self.swiftDemangleFunction = demanglerFunc // Assign passed-in pointer
        }

    // No deinit needed here for dlclose anymore

    /// Extracts basic Swift type information. Demangling uses the provided function pointer.
        func extract() throws -> ExtractedSwiftMetadata {
            var swiftMeta = ExtractedSwiftMetadata()
            guard let typesSection = findSwiftSection(named: "__swift5_types") else {
            print("ℹ️ SwiftMetadataExtractor: No __swift5_types section found.")
            return swiftMeta
        }

        print("ℹ️ SwiftMetadataExtractor: Found __swift5_types section at offset \(typesSection.command.offset), size \(typesSection.command.size). Processing...")

        let sectionStartVM = typesSection.command.addr
        let sectionStartOffset = UInt64(typesSection.command.offset)
        let sectionSize = Int(typesSection.command.size)
        let pointerSize = RELATIVE_POINTER_SIZE // Int32 size

        var currentOffsetWithinSection: Int = 0
        var typesFoundCount = 0

        while currentOffsetWithinSection < sectionSize {
            let relativePointerFileOffset = sectionStartOffset + UInt64(currentOffsetWithinSection)
            let relativePointerVMAddr = sectionStartVM + UInt64(currentOffsetWithinSection)

            // Bounds check before reading the relative pointer itself
            guard (relativePointerFileOffset + UInt64(pointerSize)) <= (sectionStartOffset + UInt64(sectionSize)) &&
                  (relativePointerFileOffset + UInt64(pointerSize)) <= parsedData.dataRegion.count
            else {
                print("Warning: SwiftMetadataExtractor - Reading Swift type pointer out of bounds.")
                break // Stop processing if we hit boundary issues
            }

            // Read the Int32 relative offset
            let relativeOffset: Int32 = try parsedData.dataRegion.read(at: Int(relativePointerFileOffset))

            // Resolve pointer to get the descriptor's VM address
            guard let descriptorVMAddr = resolveRelativePointer(baseAddress: relativePointerVMAddr, relativeOffset: relativeOffset) else {
                // Null pointer offset, expected way to terminate some lists or skip entries
                currentOffsetWithinSection += pointerSize
                continue
            }

            // Parse the descriptor at the resolved address
            do {
                if var typeInfo = try parseTypeDescriptor(at: descriptorVMAddr) {
                    // Attempt demangling using the helper method
                    typeInfo.demangledName = self.demangle(mangledName: typeInfo.mangledName)
                    swiftMeta.types.append(typeInfo)
                    typesFoundCount += 1
                }
                // If parseTypeDescriptor returned nil (e.g., skipped type), just continue
            } catch let error as MachOParseError {
                // Log specific parsing errors but continue processing the section
                print("Warning: SwiftMetadataExtractor - Failed to parse descriptor at 0x\(String(descriptorVMAddr, radix: 16)): \(error.localizedDescription)")
            } catch {
                 print("Warning: SwiftMetadataExtractor - Unknown error parsing descriptor at 0x\(String(descriptorVMAddr, radix: 16)): \(error)")
            }

            // Move to the next pointer in the __swift5_types section
            currentOffsetWithinSection += pointerSize
        }

        print("ℹ️ SwiftMetadataExtractor: Finished processing __swift5_types. Found \(typesFoundCount) type descriptors.")
        return swiftMeta
    }

    /// Finds a Swift metadata section by name within the __TEXT segment.
    private func findSwiftSection(named sectionName: String) -> ParsedSection? {
        // Primarily look in __TEXT, but could add fallbacks if needed
        return parsedData.section(segmentName: "__TEXT", sectionName: sectionName)
    }

    /// Parses a Type Context Descriptor at a given VM address.
    private func parseTypeDescriptor(at vmAddress: UInt64) throws -> SwiftTypeInfo? {
        let fileOffset = try parser.fileOffset(for: vmAddress, parsedData: parsedData)

        let flagsOffset = Int(fileOffset)
        let parentRelPtrOffset = flagsOffset + MemoryLayout<UInt32>.size
        let nameRelPtrOffset = parentRelPtrOffset + RELATIVE_POINTER_SIZE

        // Check if we can read at least up to the name pointer offset
        guard nameRelPtrOffset + RELATIVE_POINTER_SIZE <= parsedData.dataRegion.count else {
             print("Warning: SwiftMetadataExtractor - Descriptor header read out of bounds at VM 0x\(String(vmAddress, radix: 16))")
             return nil
        }

        let flagsValue: UInt32 = try parsedData.dataRegion.read(at: flagsOffset)
        let flags = TypeContextDescriptorFlags(value: flagsValue)
        let kind = flags.kindString
        var mangledName: String = "<\(kind)_NoName>"
        var nameRelOffset: Int32 = 0

        // Read specific descriptor struct based on kind to get name offset
        do {
            switch flags.kind {
            case 16: // Class
                 // Check bounds before reading the specific struct
                guard flagsOffset + MemoryLayout<TargetClassDescriptor>.stride <= parsedData.dataRegion.count else {
                     throw MachOParseError.dataReadOutOfBounds(offset: flagsOffset, length: MemoryLayout<TargetClassDescriptor>.stride, totalSize: parsedData.dataRegion.count)
                 }
                let classDesc: TargetClassDescriptor = try parsedData.dataRegion.read(at: flagsOffset)
                nameRelOffset = classDesc.name // Read relative offset from struct
            case 17, 18: // Struct, Enum
                 // Check bounds before reading the specific struct
                guard flagsOffset + MemoryLayout<TargetValueTypeDescriptor>.stride <= parsedData.dataRegion.count else {
                    throw MachOParseError.dataReadOutOfBounds(offset: flagsOffset, length: MemoryLayout<TargetValueTypeDescriptor>.stride, totalSize: parsedData.dataRegion.count)
                }
                let valueDesc: TargetValueTypeDescriptor = try parsedData.dataRegion.read(at: flagsOffset)
                nameRelOffset = valueDesc.name // Read relative offset from struct
            case 3: // Protocol
                 // TODO: Implement parsing for TargetProtocolDescriptor if needed
                 print("Note: Skipping Protocol descriptor parsing (Kind 3).")
                 return nil
            default:
                print("Note: Skipping unknown descriptor kind \(flags.kind)")
                return nil
            }
        } catch let error as MachOParseError where error.isOutOfBoundsError {
            // Catch bounds errors specifically from reading the larger struct
             print("Warning: SwiftMetadataExtractor - Reading specific descriptor (kind \(flags.kind)) out of bounds at VM 0x\(String(vmAddress, radix: 16))")
            return nil // Skip this descriptor
        }
        // Let other errors propagate up (e.g., mmap errors)


        // Resolve the relative pointer to the mangled name string
        let namePointerAddress = vmAddress + UInt64(nameRelPtrOffset - flagsOffset) // Address *of* the name field
        if let nameVMAddr = resolveRelativePointer(baseAddress: namePointerAddress, relativeOffset: nameRelOffset) {
             do {
                 let nameFileOffset = try parser.fileOffset(for: nameVMAddr, parsedData: parsedData)
                 mangledName = try parsedData.dataRegion.readCString(at: Int(nameFileOffset))
             } catch {
                  print("Warning: SwiftMetadataExtractor - Failed to read Swift mangled name string at VM 0x\(String(nameVMAddr, radix: 16)): \(error)")
                  mangledName = "<\(kind)_NameReadError>"
             }
        } else if nameRelOffset != 0 { // Only log if offset was non-zero but failed resolution
             print("Warning: SwiftMetadataExtractor - Failed to resolve relative name pointer (\(nameRelOffset)) from address 0x\(String(namePointerAddress, radix: 16))")
            mangledName = "<\(kind)_NamePtrResolveError>"
        } else {
             // Name offset was zero, expected for anonymous contexts?
             mangledName = "<\(kind)_Anonymous>"
        }

        // Return basic info, demangledName will be filled later by caller
        return SwiftTypeInfo(mangledName: mangledName, demangledName: nil, kind: kind, location: vmAddress)
    }

    // MARK: - Demangling Helper (Uses stored function pointer)

    /// Demangles a single Swift symbol name using the loaded function pointer.
    /// Returns the original mangled name if demangling is unavailable or fails.
        private func demangle(mangledName: String) -> String? {
           guard let demangleFunc = self.swiftDemangleFunction else {
               return mangledName // Return original if demangler unavailable
           }

            var result: String = mangledName; mangledName.withCString { mptr in if let dptr = demangleFunc(mptr, strlen(mptr), nil, nil, 0) { result = String(cString: dptr); free(dptr); } }; return result

       // Use withCString for safety
       mangledName.withCString { mangledPtr in
           // Call the C function _swift_demangle
           // It returns a pointer to a *newly allocated* C string that the caller must free()
           if let demangledPtr = demangleFunc(mangledPtr, strlen(mangledPtr), nil, nil, 0) {
               // Copy the C string result to a Swift String
               result = String(cString: demangledPtr)
               // CRITICAL: Free the memory allocated by _swift_demangle
               free(demangledPtr)
           } else {
               // Demangling failed for this specific name, result remains the mangledName
               // print("Warning: Demangling failed for '\(mangledName)'")
           }
       }
       return result
   }
}

// MARK: - Helper Extension for MachOParseError
extension MachOParseError {
    // Assume isOutOfBoundsError is defined elsewhere or add it here
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
// func resolveRelativePointer(baseAddress: UInt64, relativeOffset: Int32) -> UInt64? { ... }
