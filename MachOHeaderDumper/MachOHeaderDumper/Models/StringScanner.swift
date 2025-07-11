//
//  StringScanner.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Utils/StringScanner.swift

import Foundation

class StringScanner {

    // Sections commonly containing C strings
    // We can refine this list
    private static let stringSections = [
        // Segment    Section Name
        ("__TEXT", "__cstring"),
        ("__TEXT", "__objc_classname"),
        ("__TEXT", "__objc_methname"),
        ("__TEXT", "__objc_methtype"),
        ("__RODATA", "__cfstring"), // CFString data (needs more complex parsing) - Skip for now
        ("__DATA", "__cfstring"),   // CFString data (needs more complex parsing) - Skip for now
        ("__TEXT", "__const"),      // Sometimes contains strings
        ("__DATA", "__const"),      // Sometimes contains strings
        ("__DATA", "__data")        // Sometimes contains strings
        // Add Swift string sections if identifiable? e.g. __swift5_reflstr
    ]

    /// Scans predefined sections within the Mach-O data for null-terminated C strings.
    /// - Parameter parsedData: The parsed Mach-O data containing sections and the data region.
    /// - Returns: An array of FoundString objects.
    static func scanForStrings(in parsedData: ParsedMachOData) -> [FoundString] {
        var foundStrings: [FoundString] = []
        let minLength = 4 // Minimum length for a sequence to be considered a potential string

        print("StringScanner: Starting scan...")

        for (segName, sectName) in stringSections {
            guard let section = parsedData.section(segmentName: segName, sectionName: sectName) else {
                // Section doesn't exist in this binary, skip it
                continue
            }

            print("StringScanner: Scanning \(segName)/\(sectName)...")

            let sectionOffset = Int(section.command.offset)
            let sectionSize = Int(section.command.size)
            let sectionVMAddr = section.command.addr

            // Ensure section offsets/sizes are valid within the dataRegion
            guard sectionOffset >= 0, sectionSize > 0,
                  sectionOffset + sectionSize <= parsedData.dataRegion.count else {
                print("Warning: StringScanner: Invalid bounds for section \(segName)/\(sectName)")
                continue
            }

            // Get a slice of the data region for this section
            guard let sectionRegion = try? parsedData.dataRegion.slice(offset: sectionOffset, length: sectionSize) else {
                 print("Warning: StringScanner: Failed to slice data for section \(segName)/\(sectName)")
                 continue
            }

            var currentOffset: Int = 0
            while currentOffset < sectionSize {
                // Find the next potential C string start within the section slice
                // Look for printable ASCII chars or potential UTF-8 start bytes
                guard let potentialStart = sectionRegion[currentOffset...].firstIndex(where: { byte in
                    // Simple check: is printable ASCII or potential multi-byte start?
                    // Refine this check for better UTF-8 handling if needed.
                    let char = Character(UnicodeScalar(byte))
                    return byte >= 32 && byte <= 126 // Printable ASCII
                           // || (byte & 0xC0) == 0xC0 // Potential start of multi-byte UTF-8 - commented out for simplicity
                }) else {
                    // No more printable characters found in the remainder of the section
                    break
                }

                // Now, starting from potentialStart, find the next null terminator
                var length = 0
                var endOffset = potentialStart
                while endOffset < sectionRegion.count && sectionRegion[endOffset] != 0 {
                    length += 1
                    endOffset += 1
                }

                // If we found a null terminator *and* the length meets the minimum requirement
                if endOffset < sectionRegion.count && length >= minLength {
                    let stringData = sectionRegion[potentialStart..<endOffset]
                    if let str = String(data: Data(stringData), encoding: .utf8) ?? String(data: Data(stringData), encoding: .ascii) {
                        // Calculate VM address and File offset for the found string
                        let stringFileOffset = UInt64(sectionOffset + potentialStart)
                        let stringVMAddress = sectionVMAddr + UInt64(potentialStart - currentOffset) // Adjust VM offset calculation based on start

                        foundStrings.append(FoundString(
                            string: str,
                            address: stringVMAddress,
                            fileOffset: stringFileOffset,
                            sectionName: "\(segName)/\(sectName)"
                        ))

                        // Move past the found string and its null terminator
                        currentOffset = endOffset + 1
                    } else {
                        // Couldn't decode data, move past the potential start
                        currentOffset = potentialStart + 1
                    }
                } else {
                    // No null terminator found after potential start, or too short.
                    // Move past the potential start to continue scanning.
                    currentOffset = potentialStart + 1
                }
            } // End while currentOffset < sectionSize
        } // End for section loop

        print("StringScanner: Found \(foundStrings.count) strings.")
        // Optional: Sort or deduplicate strings here if desired
        return foundStrings.sorted { $0.fileOffset < $1.fileOffset }
    }
}
