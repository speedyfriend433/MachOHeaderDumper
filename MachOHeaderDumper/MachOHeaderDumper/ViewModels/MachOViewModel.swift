//
//  MachOViewModel.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: ViewModels/MachOViewModel.swift (Complete Code - Corrected Swift Section Check)

import Foundation
import SwiftUI

@MainActor
class MachOViewModel: ObservableObject {

    // --- Input/State ---
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String = "Select a file to parse."
    @Published var showIvarsInHeader: Bool = false

    // --- Output Data ---
    @Published var parsedData: ParsedMachOData?
    @Published var parsedDyldInfo: ParsedDyldInfo?
    @Published var extractedClasses: [ObjCClass] = []
    @Published var extractedProtocols: [ObjCProtocol] = []
    @Published var extractedSwiftTypes: [SwiftTypeInfo] = []
    @Published var generatedHeader: String?
    @Published var processingUpdateId = UUID()
    @Published var demanglerStatus: DemanglerStatus = .idle
    @Published var foundStrings: [FoundString] = []
    @Published var functionStarts: [FunctionStart] = []
    @Published var selectorReferences: [SelectorReference] = []

    private var currentParser: MachOParser?

    // --- Main processing function ---
    func processURL(_ url: URL) {
        // Reset state
        self.isLoading = true
        self.errorMessage = nil
        self.parsedData = nil
        self.parsedDyldInfo = nil
        self.extractedClasses = []
        self.extractedProtocols = []
        self.extractedSwiftTypes = []
        self.generatedHeader = nil
        self.demanglerStatus = .idle
        self.foundStrings = []
        self.functionStarts = []
        self.statusMessage = "Processing \(url.lastPathComponent)..."
        self.currentParser = nil
        self.selectorReferences = []

        Task.detached(priority: .userInitiated) {
            // Local task variables
            var taskParser: MachOParser? = nil
            var taskParsedDataResult: ParsedMachOData? = nil
            var taskDyldInfoResult: ParsedDyldInfo? = nil
            var taskSwiftMetaResult: ExtractedSwiftMetadata? = nil
            var taskObjCMetaResult: ExtractedMetadata? = nil
            var taskHeaderTextResult: String? = nil
            var taskFoundStringsResult: [FoundString]? = nil
            var taskFunctionStartsResult: [FunctionStart]? = nil
            var taskErrorResult: Error? = nil
            var taskObjCNotFoundErr: MachOParseError? = nil
            var taskDemanglerFunc: DynamicSymbolLookup.SwiftDemangleFunc? = nil
            var taskDemanglerStatus: DemanglerStatus = .idle

            do {
                // --- Step 0: Resolve Path ---
                let binaryURL = try self.resolveBinaryPath(for: url)
                await MainActor.run { self.statusMessage = "Parsing \(binaryURL.lastPathComponent)..." }

                // --- Step 1: Parse Mach-O Structure ---
                taskParser = MachOParser(fileURL: binaryURL)
                guard let parser = taskParser else { throw MachOParseError.mmapFailed(error: "Failed to initialize parser") }
                taskParsedDataResult = try await Task { try parser.parse() }.value
                guard let parsedResult = taskParsedDataResult else { throw MachOParseError.mmapFailed(error: "Parsing returned nil data") }

                await MainActor.run {
                    self.parsedData = parsedResult // Set parsedData early for status funcs
                    self.currentParser = parser
                    self.statusMessage = self.generateSummary(for: parsedResult) + " Lookup demangler..." // Update status
                    print("✅ Successfully parsed: \(binaryURL.lastPathComponent)")
                    if parsedResult.isEncrypted { print("⚠️ Binary is marked as encrypted.") }
                }

                // --- Step 1.1 (NEW): Scan for Strings ---
                                // Can run concurrently or sequentially. Let's do it sequentially for now.
                                 await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Scanning strings..." }
                                // Use static scanner method
                                taskFoundStringsResult = StringScanner.scanForStrings(in: parsedResult) // Assign to local var
                                print("✅ Scanned for strings.")
                
                // --- Step 1.2 (NEW): Parse Function Starts ---
                                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Parsing func starts..." }
                                do {
                                    let addresses = try FunctionStartsParser.parseFunctionStarts(in: parsedResult)
                                    // Convert addresses to FunctionStart structs
                                    taskFunctionStartsResult = addresses.map { FunctionStart(address: $0) }
                                    print("✅ Parsed \(taskFunctionStartsResult?.count ?? 0) function starts.")
                                } catch let error as FunctionStartsParseError where error == .commandNotFound {
                                     print("ℹ️ LC_FUNCTION_STARTS not found.")
                                     taskFunctionStartsResult = [] // Indicate parsing ran but found nothing
                                } catch {
                                     print("❌ Error parsing function starts: \(error)")
                                     // Treat as non-fatal for now?
                                      await MainActor.run { self.errorMessage = "Warning: Function starts parsing failed: \(error.localizedDescription)" }
                                      taskFunctionStartsResult = nil // Indicate failure
                                }
                
                // --- Step 1.3: Lookup Demangler ---
                let lookupResult = DynamicSymbolLookup.getSwiftDemangleFunctionPointer(forBinaryPath: binaryURL.path)
                taskDemanglerFunc = lookupResult.function
                taskDemanglerStatus = lookupResult.status
                await MainActor.run { self.demanglerStatus = taskDemanglerStatus } // Update UI status

                // --- Step 1.5: Parse Dyld Info ---
                guard let currentParser = taskParser else { throw MachOParseError.mmapFailed(error: "Parser became nil unexpectedly") } // Use taskParser
                do {
                    let dyldParser = try DyldInfoParser(parsedData: parsedResult)
                    taskDyldInfoResult = try dyldParser.parseAll()
                    print("✅ Successfully parsed dyld binding info.")
                } catch let error as DyldInfoParseError where error == .missingDyldInfoCommand {
                     print("ℹ️ Dyld info command not found.")
                } catch {
                     print("❌ Error parsing dyld binding info: \(error)")
                }
                // Update status after dyld parsing
                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting Swift..." }

                // --- Step 2a: Attempt Swift Extraction ---
                // FIX: Correctly check for the Swift types section
                let swiftTypesSectionExists = parsedResult.loadCommands.contains { command in
                    if case .segment64(let segCmd, let sections) = command {
                        // Use helper to get segment name
                        let segmentName = stringFromCChar16Tuple(segCmd.segname)
                        return segmentName == "__TEXT" && sections.contains { $0.name == "__swift5_types" }
                    }
                    return false
                }

                if swiftTypesSectionExists {
                     await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting Swift..." } // Update status *before* extraction
                     do {
                         let swiftExtractor = SwiftMetadataExtractor(parsedData: parsedResult,
                                                                    parser: currentParser,
                                                                    demanglerFunc: taskDemanglerFunc) // Pass pointer
                         taskSwiftMetaResult = try swiftExtractor.extract()
                         print("✅ Extracted Swift metadata (\(taskSwiftMetaResult?.types.count ?? 0) types).")
                     } catch {
                         print("⚠️ Warning: Swift metadata extraction failed: \(error)")
                     }
                 } else {
                      // Swift section not found, update demangler status if it wasn't already set
                      if taskDemanglerStatus == .idle { taskDemanglerStatus = .notAttempted }
                      print("ℹ️ No Swift sections found, skipping Swift extraction.")
                 }
                 // Update status before ObjC extraction
                 await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting ObjC..." }


                // --- Step 2b: Attempt ObjC Extraction ---
                do {
                    let extractor = ObjCMetadataExtractor(parsedData: parsedResult, parser: currentParser)
                    taskObjCMetaResult = try await extractor.extract()
                    print("✅ Successfully extracted ObjC metadata.")
                } catch let error as MachOParseError where error == .noObjectiveCMetadataFound {
                    print("ℹ️ No Objective-C metadata found.")
                    taskObjCNotFoundErr = error
                } catch { throw error }


                // --- Step 3: Generate Header (ObjC only for now) ---
                if let validObjCMeta = taskObjCMetaResult {
                    let headerGenerator = HeaderGenerator(metadata: validObjCMeta)
                    let includeIvars = await MainActor.run { self.showIvarsInHeader }
                    taskHeaderTextResult = try await headerGenerator.generateHeader(includeIvarsInHeader: includeIvars)
                    print("✅ Successfully generated ObjC header.")
                }

            } catch { // Catch outer errors
                taskErrorResult = error
                print("❌ Error during processing: \(error)")
            }

            // --- Final Update on MainActor ---
                        await MainActor.run {
                            // Assign all results collected in background to @Published properties FIRST
                            self.currentParser = taskParser
                            self.parsedData = taskParsedDataResult
                            self.foundStrings = taskFoundStringsResult ?? []
                            self.functionStarts = taskFunctionStartsResult ?? []
                            self.parsedDyldInfo = taskDyldInfoResult
                            self.extractedSwiftTypes = taskSwiftMetaResult?.types ?? [] // Assign Swift types

                            // Assign ObjC types using the explicit intermediate arrays
                            var finalClasses: [ObjCClass] = []
                            var finalProtocols: [ObjCProtocol] = []
                            if let objcMeta = taskObjCMetaResult {
                                finalClasses = Array(objcMeta.classes.values)
                                finalProtocols = Array(objcMeta.protocols.values)
                            }
                            self.extractedClasses = finalClasses.sorted { $0.name < $1.name }
                            self.extractedProtocols = finalProtocols.sorted { $0.name < $1.name }
                            self.selectorReferences = taskObjCMetaResult?.selectorReferences ?? []

                            self.generatedHeader = taskHeaderTextResult // Assign header
                            self.demanglerStatus = taskDemanglerStatus // Assign final demangler status

                            self.isLoading = false // Finish loading AFTER all data assignments

                            // Set final status and error messages based on outcomes
                            if let error = taskErrorResult {
                                // Fatal error occurred
                                self.errorMessage = "Error: \(error.localizedDescription)"
                                self.statusMessage = "Error processing file."
                                if taskParsedDataResult == nil { self.parsedData = nil }

                            } else if let objcError = taskObjCNotFoundErr {
                                 // Only non-fatal "No ObjC Meta" occurred
                                 self.errorMessage = objcError.localizedDescription
                                 // Base status on the successfully parsed data (now in self.parsedData)
                                 guard let pd = self.parsedData else {
                                      self.statusMessage = "Error: State inconsistency."; return
                                 }
                                 var finalStatus = self.generateSummary(for: pd) + " No ObjC metadata."
                                 // Use the UPDATED self.extractedSwiftTypes property here
                                 if !self.extractedSwiftTypes.isEmpty {
                                     finalStatus += " Found \(self.extractedSwiftTypes.count) Swift types."
                                 } else if taskSwiftMetaResult != nil { // Check if Swift extraction ran
                                     finalStatus += " No Swift types found."
                                 }
                                 self.statusMessage = finalStatus

                             } else {
                                // Success path
                                self.errorMessage = nil
                                guard let pd = self.parsedData else {
                                     self.statusMessage = "Error: State inconsistency."; return
                                }
                                var finalStatus = self.generateSummary(for: pd)
                                // Use the UPDATED self.extractedClasses property here
                                if !self.extractedClasses.isEmpty {
                                    finalStatus += " Found \(self.extractedClasses.count) classes."
                                } else if taskObjCMetaResult != nil { // Check if ObjC extraction ran
                                    finalStatus += " No ObjC classes found."
                                }
                                // Use the UPDATED self.extractedSwiftTypes property here
                                if !self.extractedSwiftTypes.isEmpty {
                                     finalStatus += " Found \(self.extractedSwiftTypes.count) Swift types."
                                } else if taskSwiftMetaResult != nil { // Check if Swift extraction ran
                                     finalStatus += " No Swift types found."
                                }
                                 if !self.foundStrings.isEmpty { finalStatus += " Found \(self.foundStrings.count) strings." } // <-- ADD String Count
                                 if !self.functionStarts.isEmpty { finalStatus += " Found \(self.functionStarts.count) func starts." } // <-- ADD Count
                                 if !self.selectorReferences.isEmpty { finalStatus += " Found \(self.selectorReferences.count) sel refs." } // <-- ADD Count
                                                      self.statusMessage = finalStatus.contains("Found") ? finalStatus : "Processing complete."
                                                  }

                            // --- Trigger UI update via counter ---
                            // Do this LAST after all state is set
                            self.processingUpdateId = UUID()

                        } // End MainActor.run
                    } // End Task.detached
                } // End processURL

    // --- Helper Functions ---

    // Should remain nonisolated
    private nonisolated func resolveBinaryPath(for url: URL) throws -> URL {
        // ... implementation ...
        var isDirectory: ObjCBool = false; guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return url }; let fm = FileManager.default; let ext = url.pathExtension.lowercased(); if ext == "app" || ext == "framework" { let infoURL = url.appendingPathComponent("Info.plist"); guard fm.fileExists(atPath: infoURL.path) else { let defName = url.deletingPathExtension().lastPathComponent; let binURL = url.appendingPathComponent(defName); return fm.fileExists(atPath: binURL.path) ? binURL : url }; do { let data = try Data(contentsOf: infoURL); if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String:Any], let exec = plist["CFBundleExecutable"] as? String { let binURL = url.appendingPathComponent(exec); if fm.fileExists(atPath: binURL.path) { return binURL } else { throw MachOParseError.fileNotFound(path: binURL.path) } } else { let defName = url.deletingPathExtension().lastPathComponent; let binURL = url.appendingPathComponent(defName); return fm.fileExists(atPath: binURL.path) ? binURL : url } } catch { return url } } else { return url }
    }


    // generateSummary remains MainActor isolated as it reads parsedData implicitly
    private func generateSummary(for data: ParsedMachOData) -> String {
        let arch = cpuTypeToString(data.header.cputype)
        let encryptedStatus = data.isEncrypted ? " (Encrypted)" : ""
        return "Parsed \(arch)\(encryptedStatus)."
     }
}

// --- Also need to make demangleSwiftSymbols public/internal ---


