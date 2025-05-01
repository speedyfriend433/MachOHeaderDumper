//
//  DynamicSymbolLookup.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Utils/DynamicSymbolLookup.swift

import Foundation
import Darwin // For dlopen, dlsym, dlclose, dlerror

/// Utility class to perform dynamic symbol lookups using dlopen/dlsym.
/// Handles opening and closing library handles.
class DynamicSymbolLookup {

    /// Attempts to find the runtime address of a symbol within a specific binary file.
    ///
    /// - Warning: Using dlopen on arbitrary paths can be risky and depends on the execution environment (e.g., TrollStore permissions) and the nature of the target binary. It may fail due to code signing, dependencies, architecture, or if the binary is not dynamically loadable.
    ///
    /// - Parameters:
    ///   - symbolName: The name of the symbol to look up (e.g., "_swift_demangle", "main").
    ///   - binaryPath: The absolute file path to the Mach-O binary (.dylib, executable, .framework/Executable).
    /// - Returns: An opaque pointer (`UnsafeMutableRawPointer?`) to the symbol's runtime address if found, otherwise `nil`.
    static func findSymbolAddress(named symbolName: String, inBinaryAt binaryPath: String) -> UnsafeMutableRawPointer? {
        let _ = dlerror()

        // Attempt to open the specified binary
        // RTLD_LAZY: Resolve symbols only when code is executed.
        // RTLD_NOW: Resolve symbols immediately (might fail faster if dependencies are missing).
        print("DynamicLookup: Attempting dlopen on '\(binaryPath)' for symbol '\(symbolName)'...")
        guard let handle = dlopen(binaryPath, RTLD_LAZY) else {
            let err = dlerror()
            print("DynamicLookup Error: dlopen failed for \(binaryPath): \(err != nil ? String(cString: err!) : "Unknown error")")
            return nil
        }

        defer {
            print("DynamicLookup: Closing handle for \(binaryPath)")
            if dlclose(handle) != 0 {
                let err = dlerror()
                 print("DynamicLookup Warning: dlclose failed for \(binaryPath): \(err != nil ? String(cString: err!) : "Unknown error")")
            }
        }

        guard let symbolAddress = dlsym(handle, symbolName) else {
            let err = dlerror()
            print("DynamicLookup Error: dlsym failed for symbol '\(symbolName)' in \(binaryPath): \(err != nil ? String(cString: err!) : "Symbol not found")")
            return nil
        }

        print("DynamicLookup: Successfully found address for '\(symbolName)' at \(symbolAddress)")
        return symbolAddress
    }

    /// Attempts to find a symbol within images *already loaded* into the current process.
    /// Useful for finding functions like _swift_demangle if linked or available globally.
    ///
    /// - Parameter symbolName: The name of the symbol to look up.
    /// - Returns: An opaque pointer (`UnsafeMutableRawPointer?`) to the symbol's runtime address if found, otherwise `nil`.
    static func findSymbolInLoadedImages(named symbolName: String) -> UnsafeMutableRawPointer? {
         let _ = dlerror()
         if let handle = dlopen(nil, RTLD_LAZY) {
             if let symbolAddress = dlsym(handle, symbolName) {
                 print("DynamicLookup: Found '\(symbolName)' in already loaded images at \(symbolAddress).")
                 return symbolAddress
             } else {
                  let err = dlerror()
                  print("DynamicLookup Note: '\(symbolName)' not found via dlopen(nil). \(err != nil ? String(cString: err!) : "")")
                  return nil
             }
         } else {
              let err = dlerror()
              print("DynamicLookup Warning: dlopen(nil) failed. \(err != nil ? String(cString: err!) : "")")
              return nil
         }
    }

    // more methods e.g., for finding _swift_demangle
    static func getSwiftDemangleFunctionPointer(forBinaryPath path: String? = nil) -> SwiftMetadataExtractor.SwiftDemangleFunc? {
        var symAddress: UnsafeMutableRawPointer? = nil

        symAddress = findSymbolInLoadedImages(named: "_swift_demangle")

        if symAddress == nil, let binaryPath = path {
            symAddress = findSymbolAddress(named: "_swift_demangle", inBinaryAt: binaryPath)
        }

        if let validAddress = symAddress {
             return unsafeBitCast(validAddress, to: SwiftMetadataExtractor.SwiftDemangleFunc.self)
        } else {
             return nil
        }
    }
}
