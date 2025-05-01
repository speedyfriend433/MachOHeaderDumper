//
//  SwiftMetadataExtractor.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: SwiftMetadataExtractor.swift (Complete Code with Lazy Var Fix)

import Foundation
import MachO // For constants like section names
import Darwin // For dlopen, dlsym, free

// Assume SwiftMetadataStructs.swift and SwiftModels.swift are available

class SwiftMetadataExtractor {
    // Required properties initialized normally
    private let parsedData: ParsedMachOData
    private let parser: MachOParser

    // Cache for dlopen handle if target binary is opened
    private var handleCache: UnsafeMutableRawPointer? = nil

    // Define the C function signature for _swift_demangle
    typealias SwiftDemangleFunc = @convention(c) (
        UnsafePointer<CChar>, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
    ) -> UnsafeMutablePointer<CChar>?

    // FIX: Make the function pointer a lazy var.
    // It will be initialized only when first accessed (e.g., by demangle()),
    // at which point 'self' (and thus 'parsedData') is fully initialized.
    private lazy var swiftDemangleFunction: SwiftDemangleFunc? = self.findSwiftDemangleFunction()

    init(parsedData: ParsedMachOData, parser: MachOParser) {
        // Initialize non-lazy properties as usual
        self.parsedData = parsedData
        self.parser = parser
        // No need to initialize swiftDemangleFunction here anymore
    }

    deinit {
        if let handle = handleCache {
             print("Closing dlopen handle for \(parsedData.fileURL.lastPathComponent)")
             dlclose(handle)
        }
    }

    /// Extracts basic Swift type information (kind, mangled/demangled name, location).
    func extract() throws -> ExtractedSwiftMetadata {
        var swiftMeta = ExtractedSwiftMetadata()

        guard let typesSection = findSwiftSection(named: "__swift5_types") else {
            print("ℹ️ No __swift5_types section found.")
            return swiftMeta
        }

        let sectionStartVM = typesSection.command.addr
        let sectionStartOffset = UInt64(typesSection.command.offset)
        let sectionSize = Int(typesSection.command.size)
        let pointerSize = RELATIVE_POINTER_SIZE

        var currentOffsetWithinSection: Int = 0
        while currentOffsetWithinSection < sectionSize {
            let relativePointerFileOffset = sectionStartOffset + UInt64(currentOffsetWithinSection)
            let relativePointerVMAddr = sectionStartVM + UInt64(currentOffsetWithinSection)

            guard relativePointerFileOffset + UInt64(pointerSize) <= parsedData.dataRegion.count,
                  relativePointerFileOffset + UInt64(pointerSize) <= sectionStartOffset + UInt64(sectionSize)
            else { break }

            let relativeOffset: Int32 = try parsedData.dataRegion.read(at: Int(relativePointerFileOffset))

            guard let descriptorVMAddr = resolveRelativePointer(baseAddress: relativePointerVMAddr, relativeOffset: relativeOffset) else {
                currentOffsetWithinSection += pointerSize
                continue
            }

            do {
                // parseTypeDescriptor no longer needs to be mutable for demangling here
                if let typeInfo = try parseTypeDescriptor(at: descriptorVMAddr) {
                    // Create a mutable copy to assign demangled name
                    var mutableTypeInfo = typeInfo
                    // Demangling happens when accessing the lazy var swiftDemangleFunction
                    // inside the demangle() method.
                    mutableTypeInfo.demangledName = self.demangle(mangledName: typeInfo.mangledName)
                    swiftMeta.types.append(mutableTypeInfo)
                }
            } catch {
                 print("Warning: Skipping Swift descriptor at 0x\(String(descriptorVMAddr, radix: 16)) due to error: \(error)")
            }
            currentOffsetWithinSection += pointerSize
        }

        return swiftMeta
    }

    /// Finds a Swift metadata section by name within the __TEXT segment.
    private func findSwiftSection(named sectionName: String) -> ParsedSection? {
        return parsedData.section(segmentName: "__TEXT", sectionName: sectionName)
    }

    /// Parses a Type Context Descriptor at a given VM address.
    /// Returns basic info; demangling is done separately.
    private func parseTypeDescriptor(at vmAddress: UInt64) throws -> SwiftTypeInfo? {
        let fileOffset = try parser.fileOffset(for: vmAddress, parsedData: parsedData)

        let flagsOffset = Int(fileOffset)
        let parentOffset = flagsOffset + MemoryLayout<UInt32>.size
        let nameOffsetInStruct = parentOffset + RELATIVE_POINTER_SIZE // Approx offset of name field itself

        guard flagsOffset >= 0, nameOffsetInStruct + RELATIVE_POINTER_SIZE <= parsedData.dataRegion.count else {
             print("Warning: Descriptor header read out of bounds at VM 0x\(String(vmAddress, radix: 16))")
             return nil
        }

        let flagsValue: UInt32 = try parsedData.dataRegion.read(at: flagsOffset)
        let flags = TypeContextDescriptorFlags(value: flagsValue)
        let kind = flags.kindString
        var mangledName: String = "<\(kind)_NoName>"
        var nameRelOffset: Int32 = 0

        do {
            switch flags.kind {
            case 16: // Class
                guard flagsOffset + MemoryLayout<TargetClassDescriptor>.stride <= parsedData.dataRegion.count else { throw MachOParseError.dataReadOutOfBounds(offset: flagsOffset, length: MemoryLayout<TargetClassDescriptor>.stride, totalSize: parsedData.dataRegion.count) }
                let classDesc: TargetClassDescriptor = try parsedData.dataRegion.read(at: flagsOffset)
                nameRelOffset = classDesc.name
            case 17, 18: // Struct, Enum
                guard flagsOffset + MemoryLayout<TargetValueTypeDescriptor>.stride <= parsedData.dataRegion.count else { throw MachOParseError.dataReadOutOfBounds(offset: flagsOffset, length: MemoryLayout<TargetValueTypeDescriptor>.stride, totalSize: parsedData.dataRegion.count) }
                let valueDesc: TargetValueTypeDescriptor = try parsedData.dataRegion.read(at: flagsOffset)
                nameRelOffset = valueDesc.name
            case 3: // Protocol
                print("Note: Skipping Protocol descriptor parsing for now.")
                return nil
            default:
                print("Note: Skipping unknown descriptor kind \(flags.kind)")
                return nil
            }
        } catch let error as MachOParseError where error.isOutOfBoundsError {
             print("Warning: Failed reading specific descriptor (kind \(flags.kind)) due to bounds at VM 0x\(String(vmAddress, radix: 16))")
            return nil
        } catch {
            print("Warning: Error reading specific descriptor (kind \(flags.kind)) at VM 0x\(String(vmAddress, radix: 16)): \(error)")
            return nil
        }


        let namePointerAddress = vmAddress + UInt64(nameOffsetInStruct - flagsOffset) // Address of name field
        if let nameVMAddr = resolveRelativePointer(baseAddress: namePointerAddress, relativeOffset: nameRelOffset) {
             do {
                 let nameFileOffset = try parser.fileOffset(for: nameVMAddr, parsedData: parsedData)
                 mangledName = try parsedData.dataRegion.readCString(at: Int(nameFileOffset))
             } catch {
                  print("Warning: Failed to read Swift mangled name string at VM 0x\(String(nameVMAddr, radix: 16)): \(error)")
                  mangledName = "<\(kind)_NameReadError>"
             }
        } else {
            mangledName = "<\(kind)_NoNamePtr>"
        }

        // Return info with demangledName as nil initially
        return SwiftTypeInfo(mangledName: mangledName, demangledName: nil, kind: kind, location: vmAddress)
    }

    // MARK: - Demangling Implementation

    /// Attempts to find the _swift_demangle function pointer using dlsym.
    /// Called only when the lazy var 'swiftDemangleFunction' is first accessed.
    private func findSwiftDemangleFunction() -> SwiftDemangleFunc? {
        print("Attempting to find _swift_demangle...")
        let _ = dlerror() // Clear previous errors

        // Option 1: Look in default loaded images
        if let handle = dlopen(nil, RTLD_LAZY) {
            if let sym = dlsym(handle, "_swift_demangle") {
                print("ℹ️ Found _swift_demangle in loaded images via dlopen(nil).")
                return unsafeBitCast(sym, to: SwiftDemangleFunc.self)
            } else {
                 let err = dlerror(); print("Note: _swift_demangle not found via dlopen(nil). \(err != nil ? String(cString: err!) : "")")
            }
            // dlclose(handle) - Don't close handle from dlopen(nil)
        } else {
             let err = dlerror(); print("Warning: dlopen(nil) failed. \(err != nil ? String(cString: err!) : "")")
        }

        // Option 2: Try opening the target binary
        let binaryPath = self.parsedData.fileURL.path // Accessing self here is OK because lazy var is accessed after init
        print("Attempting to dlopen target binary for demangler: \(binaryPath)")
        // Ensure handleCache isn't already set from a previous attempt if this func could be called again (it shouldn't with lazy var)
        if self.handleCache == nil {
            self.handleCache = dlopen(binaryPath, RTLD_LAZY)
        }

        if let specificHandle = self.handleCache {
            if let sym = dlsym(specificHandle, "_swift_demangle") {
                print("ℹ️ Found _swift_demangle by dlopen'ing target binary.")
                // Keep handleCache open, will be closed in deinit
                return unsafeBitCast(sym, to: SwiftDemangleFunc.self)
            } else {
                 let err = dlerror(); print("Warning: _swift_demangle not found in target binary. \(err != nil ? String(cString: err!) : "")")
                 dlclose(specificHandle) // Close handle if symbol not found this time
                 self.handleCache = nil
            }
        } else {
             let err = dlerror(); print("Warning: Failed to dlopen target binary '\(binaryPath)'. \(err != nil ? String(cString: err!) : "")")
        }

        print("Warning: _swift_demangle function pointer could not be obtained. Demangling disabled.")
        return nil
    }

    /// Demangles a single Swift symbol name using the loaded function pointer.
    private func demangle(mangledName: String) -> String? {
       // Accessing the lazy var here triggers findSwiftDemangleFunction if needed
       guard let demangleFunc = self.swiftDemangleFunction else {
           return mangledName // Return original if demangler unavailable
       }

       var result: String? = nil
       mangledName.withCString { mangledPtr in
           if let demangledPtr = demangleFunc(mangledPtr, strlen(mangledPtr), nil, nil, 0) {
               result = String(cString: demangledPtr)
               free(demangledPtr) // Free the C string allocated by the demangler
           } else {
               // Demangling failed for this specific name
               // print("Warning: Demangling failed for '\(mangledName)'")
               result = mangledName // Fallback
           }
       }
       return result
   }
}

// --- Helper Extension for MachOParseError ---
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
