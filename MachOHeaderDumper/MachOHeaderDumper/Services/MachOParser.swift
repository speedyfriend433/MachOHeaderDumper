//
//  MachOParser.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: MachOParser.swift (Corrected LC_ constant casting)

import Foundation
import MachO        // Or rely on manual definitions
import CryptoKit

// MARK: - MachO Parser Class

class MachOParser {
    let fileURL: URL
    private var fileHandle: FileHandle?
    private var mappedRegion: UnsafeMutableRawPointer?
    private var totalFileSize: Int = 0
    private var fullFileRegion: UnsafeRawBufferPointer?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        unmapFile()
    }

    /// Parses the Mach-O file. Selects ARM64 architecture by default from Fat binaries.
        func parse() throws -> ParsedMachOData {
            try mapFile()
            guard let fullRegion = fullFileRegion else {
                throw MachOParseError.mmapFailed(error: "Mapped region is nil after mapFile.")
            }

            let magic: UInt32 = try fullRegion.read(at: 0)

            var isSourceByteSwapped = false
            var machoDataRegion: UnsafeRawBufferPointer

            switch magic {
            case FAT_MAGIC:
                isSourceByteSwapped = false
                machoDataRegion = try parseFatHeader(region: fullRegion, isSwapped: isSourceByteSwapped)
            case FAT_CIGAM:
                isSourceByteSwapped = true
                machoDataRegion = try parseFatHeader(region: fullRegion, isSwapped: isSourceByteSwapped)
            case MH_MAGIC_64:
                 isSourceByteSwapped = false
                 machoDataRegion = fullRegion
            case MH_CIGAM_64:
                 throw MachOParseError.byteSwapRequiredButNotImplemented // Keep error for thin swapped files
            default:
                throw MachOParseError.invalidMagicNumber(magic: magic)
            }

            // Now parse the selected thin Mach-O slice
            return try parseThinHeader(region: machoDataRegion, sourceByteSwapped: isSourceByteSwapped)
        }

    // MARK: - File Mapping
    // mapFile() and unmapFile() remain the same...
     private func mapFile() throws {
         guard FileManager.default.fileExists(atPath: fileURL.path) else {
             throw MachOParseError.fileNotFound(path: fileURL.path)
         }
         do {
             fileHandle = try FileHandle(forReadingFrom: fileURL)
         } catch {
             throw MachOParseError.failedToOpenFile(path: fileURL.path, error: error)
         }
         guard let fh = fileHandle else {
              throw MachOParseError.failedToOpenFile(path: fileURL.path, error: NSError(domain: NSPOSIXErrorDomain, code: Int(EBADF), userInfo: nil))
         }
         let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
         guard let fileSizeNum = attributes?[.size] as? NSNumber, fileSizeNum.intValue > 0 else {
             throw MachOParseError.failedToGetFileSize(path: fileURL.path)
         }
         self.totalFileSize = fileSizeNum.intValue
         let fd = fh.fileDescriptor
         mappedRegion = mmap(nil, totalFileSize, PROT_READ, MAP_PRIVATE, fd, 0)
         guard let validRegion = mappedRegion, validRegion != MAP_FAILED else {
             let errorString = String(cString: strerror(errno))
             mappedRegion = nil
             throw MachOParseError.mmapFailed(error: errorString)
         }
         fullFileRegion = UnsafeRawBufferPointer(start: validRegion, count: totalFileSize)
     }
     private func unmapFile() {
         if let region = mappedRegion, totalFileSize > 0 {
             munmap(region, totalFileSize)
         }
         mappedRegion = nil
         fullFileRegion = nil
         try? fileHandle?.close()
         fileHandle = nil
         totalFileSize = 0
     }

    // MARK: - Fat Binary Parsing

    private func parseFatHeader(region: UnsafeRawBufferPointer, isSwapped: Bool) throws -> UnsafeRawBufferPointer {
           var header: fat_header = try region.read(at: 0)
           if isSwapped { header.nfat_arch = header.nfat_arch.byteSwapped }
           guard header.magic == FAT_MAGIC || header.magic == FAT_CIGAM else { throw MachOParseError.fatHeaderReadError }
           guard header.nfat_arch > 0 else { throw MachOParseError.fatHeaderReadError }

           var archs: [fat_arch] = []
           var currentOffset = MemoryLayout<fat_header>.size
           for _ in 0..<header.nfat_arch {
               guard currentOffset + MemoryLayout<fat_arch>.size <= region.count else { throw MachOParseError.fatArchReadError }
               var arch: fat_arch = try region.read(at: currentOffset)
               if isSwapped {
                    arch.cputype = arch.cputype.byteSwapped
                    arch.cpusubtype = arch.cpusubtype.byteSwapped
                    arch.offset = arch.offset.byteSwapped
                    arch.size = arch.size.byteSwapped
                    arch.align = arch.align.byteSwapped
               }
               archs.append(arch)
               currentOffset += MemoryLayout<fat_arch>.size
           }

           let desiredCpuType: cpu_type_t = CPU_TYPE_ARM64
           if let selectedArch = archs.first(where: { $0.cputype == desiredCpuType }) {
                // Found desired arch
                return try region.slice(offset: Int(selectedArch.offset), length: Int(selectedArch.size))
           } else {
                // Fallback: Use the first architecture if desired not found
                // FIX: Directly use archs.first properties, removing unused 'firstArch' variable warning
                guard let firstArchProps = archs.first else {
                    // This case should be impossible due to guard nfat_arch > 0 above, but handle defensively
                    throw MachOParseError.architectureNotFound(cpuType: desiredCpuType)
                }
                print("Warning: Desired architecture \(cpuTypeToString(desiredCpuType)) not found. Selecting first available: \(cpuTypeToString(firstArchProps.cputype))")
                return try region.slice(offset: Int(firstArchProps.offset), length: Int(firstArchProps.size))
           }
       }


    // MARK: - Thin Binary Parsing

    private func parseThinHeader(region: UnsafeRawBufferPointer, sourceByteSwapped: Bool) throws -> ParsedMachOData {
            let header: mach_header_64 = try region.read(at: 0)
            guard header.magic == MH_MAGIC_64 else { throw MachOParseError.invalidMagicNumber(magic: header.magic) }

            var parsedCommands: [ParsedLoadCommand] = []
            var currentOffset = MemoryLayout<mach_header_64>.size
            var textSegmentVMAddr: UInt64? = nil
            var encryptionInfoDict: [UInt32: (offset: UInt32, size: UInt32)] = [:]
            var uuidCmdStruct: uuid_command? = nil
            var symtabCmdStruct: symtab_command? = nil
            var dysymtabCmdStruct: dysymtab_command? = nil

            for _ in 0..<Int(header.ncmds) {
                guard currentOffset + MemoryLayout<load_command>.size <= region.count else { throw MachOParseError.loadCommandReadError }
                let lc: load_command = try region.read(at: currentOffset)
                guard lc.cmdsize >= MemoryLayout<load_command>.size else { throw MachOParseError.loadCommandReadError }
                let nextOffset = currentOffset + Int(lc.cmdsize)
                guard nextOffset > currentOffset, nextOffset <= region.count else { throw MachOParseError.loadCommandReadError }

                // --- Parse based on command type ---
                var parsedCmd: ParsedLoadCommand? = nil

                switch lc.cmd {
                case UInt32(LC_SEGMENT_64):
                    guard lc.cmdsize >= MemoryLayout<segment_command_64>.size else { break }
                    let segmentCommand: segment_command_64 = try region.read(at: currentOffset)
                    let segmentName = ParsedSegment(command: segmentCommand, sections: []).name
                     if segmentName == "__TEXT" { textSegmentVMAddr = segmentCommand.vmaddr }
                    var sections: [ParsedSection] = []
                    var sectionOffset = currentOffset + MemoryLayout<segment_command_64>.size
                    let expectedSectionEndOffset = currentOffset + Int(segmentCommand.cmdsize)
                    for _ in 0..<Int(segmentCommand.nsects) {
                        guard sectionOffset + MemoryLayout<section_64>.size <= expectedSectionEndOffset else { throw MachOParseError.sectionReadError }
                         let sectionCommand: section_64 = try region.read(at: sectionOffset)
                         sections.append(ParsedSection(command: sectionCommand))
                         sectionOffset += MemoryLayout<section_64>.size
                    }
                    parsedCmd = .segment64(segmentCommand, sections)

                case UInt32(LC_ENCRYPTION_INFO_64):
                     guard lc.cmdsize >= MemoryLayout<encryption_info_command_64>.size else { break }
                     let encInfoCmd: encryption_info_command_64 = try region.read(at: currentOffset)
                     encryptionInfoDict[encInfoCmd.cryptid] = (offset: encInfoCmd.cryptoff, size: encInfoCmd.cryptsize)
                     parsedCmd = .encryptionInfo64(encInfoCmd)

                case UInt32(LC_UUID):
                     guard lc.cmdsize >= MemoryLayout<uuid_command>.size else { break }
                     let uuidStruct: uuid_command = try region.read(at: currentOffset)
                     uuidCmdStruct = uuidStruct
                     parsedCmd = .uuid(uuidStruct)

                case UInt32(LC_SYMTAB):
                     guard lc.cmdsize >= MemoryLayout<symtab_command>.size else { break }
                     let symStruct: symtab_command = try region.read(at: currentOffset)
                     symtabCmdStruct = symStruct
                     parsedCmd = .symtab(symStruct)

                case UInt32(LC_DYSYMTAB):
                     guard lc.cmdsize >= MemoryLayout<dysymtab_command>.size else { break }
                     let dysymStruct: dysymtab_command = try region.read(at: currentOffset)
                     dysymtabCmdStruct = dysymStruct
                     parsedCmd = .dysymtab(dysymStruct)

                 case UInt32(LC_LOAD_DYLIB), UInt32(LC_ID_DYLIB), UInt32(LC_LOAD_DYLINKER):
                      guard lc.cmdsize > MemoryLayout<dylib_command>.size else { break }
                      let dylibCmd: dylib_command = try region.read(at: currentOffset)
                      let pathOffsetInCmd = Int(dylibCmd.dylib.name)
                      let pathStartOffset = currentOffset + pathOffsetInCmd
                      let maxPathLength = Int(dylibCmd.cmdsize) - pathOffsetInCmd

                      guard pathStartOffset < nextOffset, maxPathLength > 0 else { break }

                      var path: String = "<Read Error>"
                      do {
                          let pathDataRegion = try region.slice(offset: pathStartOffset, length: maxPathLength)
                          path = try pathDataRegion.readCString(at: 0)
                      } catch {
                          print("Warning: Failed to read dylib path string for cmd \(lc.cmd): \(error)")
                      }

                    if lc.cmd == UInt32(LC_LOAD_DYLIB) { parsedCmd = .loadDylib(path, dylibCmd.dylib) }
                                      else if lc.cmd == UInt32(LC_ID_DYLIB) { parsedCmd = .idDylib(path, dylibCmd.dylib) }
                                      else { parsedCmd = .loadDylinker(path) }

                                case UInt32(LC_VERSION_MIN_MACOSX),
                                     UInt32(LC_VERSION_MIN_IPHONEOS),
                                     UInt32(LC_VERSION_MIN_WATCHOS),
                                     UInt32(LC_VERSION_MIN_TVOS):
                                    guard lc.cmdsize >= MemoryLayout<version_min_command>.size else { break }
                                    let verCmd: version_min_command = try region.read(at: currentOffset)
                                    let platformName: String
                                    switch lc.cmd {
                                        case UInt32(LC_VERSION_MIN_MACOSX): platformName = "MACOSX"
                                        case UInt32(LC_VERSION_MIN_IPHONEOS): platformName = "IPHONEOS"
                                        case UInt32(LC_VERSION_MIN_WATCHOS): platformName = "WATCHOS"
                                        case UInt32(LC_VERSION_MIN_TVOS): platformName = "TVOS"
                                        default: platformName = "UNKNOWN"
                                    }
                                    parsedCmd = .versionMin(verCmd, platformName)

                                 case UInt32(LC_BUILD_VERSION):
                                      guard lc.cmdsize >= MemoryLayout<build_version_command>.size else { break }
                                      let buildCmd: build_version_command = try region.read(at: currentOffset)
                                      parsedCmd = .buildVersion(buildCmd)

                                case UInt32(LC_SOURCE_VERSION):
                                     guard lc.cmdsize >= MemoryLayout<source_version_command>.size else { break }
                                     let srcCmd: source_version_command = try region.read(at: currentOffset)
                                     parsedCmd = .sourceVersion(srcCmd)

                                case UInt32(LC_FUNCTION_STARTS),
                                     UInt32(LC_DATA_IN_CODE),
                                     UInt32(LC_CODE_SIGNATURE):
                                     guard lc.cmdsize >= MemoryLayout<linkedit_data_command>.size else { break }
                                     let leCmd: linkedit_data_command = try region.read(at: currentOffset)
                                     if lc.cmd == UInt32(LC_FUNCTION_STARTS) { parsedCmd = .functionStarts(leCmd) }
                                     else if lc.cmd == UInt32(LC_DATA_IN_CODE) { parsedCmd = .dataInCode(leCmd) }
                                     else { parsedCmd = .codeSignature(leCmd) }

                                 case UInt32(LC_DYLD_INFO_ONLY), UInt32(LC_DYLD_INFO):
                                      guard lc.cmdsize >= MemoryLayout<dyld_info_command>.size else { break }
                                      let dyldInfoCmd: dyld_info_command = try region.read(at: currentOffset)
                                      parsedCmd = .dyldInfo(dyldInfoCmd)

                                case UInt32(LC_MAIN):
                                    guard lc.cmdsize >= MemoryLayout<entry_point_command>.size else { break }
                                    let mainCmd: entry_point_command = try region.read(at: currentOffset)
                                    parsedCmd = .main(mainCmd)

                                default:
                                     parsedCmd = .unknown(cmd: lc.cmd, cmdsize: lc.cmdsize)
                                }

                                if let cmd = parsedCmd {
                                    parsedCommands.append(cmd)
                                }

                                currentOffset = nextOffset
                            }

                var symbols: [Symbol]? = nil
                if let st = symtabCmdStruct { symbols = try parseSymbols(symtabCommand: st, region: region) }
                var dynamicSymbolInfo: DynamicSymbolTableInfo? = nil
                if let dys = dysymtabCmdStruct { dynamicSymbolInfo = parseDynamicSymbolInfo(dysymtabCommand: dys) }
                // The ParsedMachOData struct now stores the *result* of that parsing.

                let baseAddress = textSegmentVMAddr ?? 0x100000000
                let parsedUUID = uuidCmdStruct != nil ? UUID(uuid: uuidCmdStruct!.uuid) : nil

                return ParsedMachOData(
                    fileURL: self.fileURL,
                    dataRegion: region,
                    header: header,
                    baseAddress: baseAddress,
                    isSourceByteSwapped: sourceByteSwapped,
                    encryptionInfo: encryptionInfoDict,
                    uuid: parsedUUID,
                    symbols: symbols,
                    dynamicSymbolInfo: dynamicSymbolInfo,
                    loadCommands: parsedCommands,
                    dyldInfo: nil,
                    foundStrings: nil,
                    functionStarts: nil
                )
            }
    
    
    private func parseDynamicSymbolInfo(dysymtabCommand dys: dysymtab_command) -> DynamicSymbolTableInfo {
            var localRange: Range<UInt32>? = nil
            if dys.nlocalsym > 0 {
                localRange = dys.ilocalsym ..< (dys.ilocalsym + dys.nlocalsym)
            }
            var extDefRange: Range<UInt32>? = nil
            if dys.nextdefsym > 0 {
                extDefRange = dys.iextdefsym ..< (dys.iextdefsym + dys.nextdefsym)
            }
            var undefRange: Range<UInt32>? = nil
            if dys.nundefsym > 0 {
                undefRange = dys.iundefsym ..< (dys.iundefsym + dys.nundefsym)
            }

            let indirectOffset = dys.nindirectsyms > 0 ? dys.indirectsymoff : nil
            let indirectCount = dys.nindirectsyms > 0 ? dys.nindirectsyms : nil


            return DynamicSymbolTableInfo(
                localSymbolsRange: localRange,
                externalDefinedSymbolsRange: extDefRange,
                undefinedSymbolsRange: undefRange,
                indirectSymbolsOffset: indirectOffset,
                indirectSymbolsCount: indirectCount
            )
        }
    
    // MARK: - Symbol Table Parsing

    private func parseSymbols(symtabCommand st: symtab_command, region: UnsafeRawBufferPointer) throws -> [Symbol] {
            var symbols: [Symbol] = []
            let symOffset = Int(st.symoff)
            let strOffset = Int(st.stroff)
            let nsyms = Int(st.nsyms)
            let symSize = MemoryLayout<nlist_64>.size

            guard symOffset >= 0, strOffset >= 0,
                  symOffset + (nsyms * symSize) <= region.count,
                  strOffset + Int(st.strsize) <= region.count
            else {
                print("Warning: Symbol table or string table offset/size out of bounds.")
                return []
            }

            let stringTableRegion = try region.slice(offset: strOffset, length: Int(st.strsize))

            for i in 0..<nsyms {
                let currentSymOffset = symOffset + (i * symSize)
                let nl: nlist_64 = try region.read(at: currentSymOffset)
                let nameOffset = Int(nl.n_un.n_strx)
                var name = "<InvalidStrOffset>"
                if nameOffset > 0 && nameOffset < stringTableRegion.count {
                    name = (try? stringTableRegion.readCString(at: nameOffset)) ?? "<InvalidStr>"
                } else if nameOffset == 0 {
                    name = ""
                }

                // Although N_TYPE and N_EXT *should* be UInt8 from the definition,
                let typeValue = nl.n_type & UInt8(N_TYPE)
                let isExternalValue = (nl.n_type & UInt8(N_EXT)) != UInt8(0)

                let symbol = Symbol(
                    name: name,
                    type: typeValue,
                    sectionNumber: nl.n_sect,
                    description: nl.n_desc,
                    value: nl.n_value,
                    isExternal: isExternalValue
                )
                symbols.append(symbol)
            }
            return symbols
        }

    // MARK: - Pointer Resolution (Revised Relative Logic)

        func fileOffset(for vmAddress: UInt64, parsedData: ParsedMachOData) throws -> UInt64 {
            let imageBase = parsedData.baseAddress
            // Calculate the target address's offset relative to the image base
            // Handle potential underflow if vmAddress < imageBase (unlikely for valid pointers)
            guard vmAddress >= imageBase else {
                 print("      [Debug] fileOffset: ERROR - VM Address 0x\(String(vmAddress, radix: 16)) is less than image base 0x\(String(imageBase, radix: 16)).")
                 throw MachOParseError.addressResolutionFailed(vmaddr: vmAddress)
            }
            let relativeTargetOffset = vmAddress - imageBase
            print("      [Debug] fileOffset: Resolving VM 0x\(String(vmAddress, radix: 16)) (Relative Offset: 0x\(String(relativeTargetOffset, radix: 16)), Base: 0x\(String(imageBase, radix: 16)))")


            for segment in parsedData.segments {
                guard segment.command.vmaddr >= imageBase else {
                     print("        [Debug] fileOffset: Skipping segment \(segment.name) with vmaddr 0x\(String(segment.command.vmaddr, radix: 16)) below image base.")
                     continue
                }
                // Calculate segment's relative start and end offsets
                let relativeSegStart = segment.command.vmaddr - imageBase
                let segSize = segment.command.vmsize
                let relativeSegEnd = relativeSegStart + segSize

                // Check if target relative offset falls within the segment's relative VM range
                if relativeTargetOffset >= relativeSegStart && relativeTargetOffset < relativeSegEnd {
                    print("        [Debug] fileOffset: Relative offset 0x\(String(relativeTargetOffset, radix: 16)) is within segment \(segment.name) [Rel: 0x\(String(relativeSegStart, radix: 16)) - 0x\(String(relativeSegEnd, radix: 16))]")

                    // Check sections within this segment
                    for section in segment.sections {
                         guard section.command.addr >= imageBase else { continue }

                         let relativeSectStart = section.command.addr - imageBase
                         let sectSize = section.command.size
                         let relativeSectEnd = relativeSectStart + sectSize

                         if relativeTargetOffset >= relativeSectStart && relativeTargetOffset < relativeSectEnd {
                             let offsetWithinSection = relativeTargetOffset - relativeSectStart

                             // Calculate file offset using the section's base file offset
                             let fileOffset = UInt64(section.command.offset) + offsetWithinSection

                             print("        [Debug] fileOffset: Found in section \(section.name) [Rel: 0x\(String(relativeSectStart, radix: 16)) - 0x\(String(relativeSectEnd, radix: 16))]. Offset within section: \(offsetWithinSection). Final File Offset: \(fileOffset)")

                             // Sanity check final file offset against the *section's* file size (not VM size)
                             // Ensure the offset points within the part mapped from the file
                             guard offsetWithinSection < section.command.size else { // Re-check this condition logic - should maybe use section.command.filesize if different? Often size == filesize. Let's stick to size for now.
                                  print("        [Debug] fileOffset: WARNING - Offset within section (\(offsetWithinSection)) exceeds section size (\(section.command.size)) for \(section.name). Might be VM padding.")
                                  // Allow this for now, but might indicate an issue later if reading fails
                                  // throw MachOParseError.addressResolutionFailed(vmaddr: vmAddress)
                                 throw MachOParseError.addressResolutionFailed(vmaddr: vmAddress)}
                             guard fileOffset < parsedData.dataRegion.count else {
                                 print("        [Debug] fileOffset: ERROR - Calculated file offset \(fileOffset) exceeds data region size \(parsedData.dataRegion.count)")
                                 throw MachOParseError.addressResolutionFailed(vmaddr: vmAddress)
                             }
                             return fileOffset
                         }
                    }

                    // Address is in the segment but not in any specific section (e.g., header padding)
                    print("        [Debug] fileOffset: Relative offset 0x\(String(relativeTargetOffset, radix: 16)) in segment \(segment.name) but not in a specific section.")

                    // Can we map it relative to the segment's file offset? Only if it falls within the segment's *file* size.
                     let offsetWithinSegmentFile = relativeTargetOffset - relativeSegStart // Offset from start of segment's VM range
                     guard offsetWithinSegmentFile < segment.command.filesize else {
                         print("        [Debug] fileOffset: ERROR - Offset within segment (\(offsetWithinSegmentFile)) exceeds segment's file size (\(segment.command.filesize)) for \(segment.name). Cannot map to file offset.")
                         throw MachOParseError.addressResolutionFailed(vmaddr: vmAddress)
                     }

                     let fileOffset = segment.command.fileoff + offsetWithinSegmentFile
                     print("        [Debug] fileOffset: Mapping relative to segment start. Final File Offset: \(fileOffset)")

                     // Sanity check final file offset
                     guard fileOffset < parsedData.dataRegion.count else {
                         print("        [Debug] fileOffset: ERROR - Calculated segment-relative file offset \(fileOffset) exceeds data region size \(parsedData.dataRegion.count)")
                         throw MachOParseError.addressResolutionFailed(vmaddr: vmAddress)
                     }
                     return fileOffset
                } 
            }

            // Address was not found in any segment's VM range using relative offsets
            print("      [Debug] fileOffset: ERROR - Relative Offset 0x\(String(relativeTargetOffset, radix: 16)) (VM: 0x\(String(vmAddress, radix: 16))) not found in any segment.")
            throw MachOParseError.addressResolutionFailed(vmaddr: vmAddress)
        }
    }
