//
//  MachOViewModel.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: ViewModels/MachOViewModel.swift (Corrected Final Status Logic)

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
        self.statusMessage = "Processing \(url.lastPathComponent)..."
        self.currentParser = nil

        Task.detached(priority: .userInitiated) {
            // Local task variables
            var taskParser: MachOParser? = nil
            var taskParsedDataResult: ParsedMachOData? = nil
            var taskDyldInfoResult: ParsedDyldInfo? = nil
            var taskSwiftMetaResult: ExtractedSwiftMetadata? = nil
            var taskObjCMetaResult: ExtractedMetadata? = nil
            var taskHeaderTextResult: String? = nil
            var taskErrorResult: Error? = nil
            var taskObjCNotFoundErr: MachOParseError? = nil

            do {
                // --- Step 0: Resolve Path ---
                let binaryURL = try self.resolveBinaryPath(for: url)
                await MainActor.run { self.statusMessage = "Parsing \(binaryURL.lastPathComponent)..." }

                // --- Step 1: Parse Mach-O Structure ---
                taskParser = MachOParser(fileURL: binaryURL)
                guard let parser = taskParser else { throw MachOParseError.mmapFailed(error: "Failed to initialize parser") }
                taskParsedDataResult = try await Task { try parser.parse() }.value
                guard let parsedResult = taskParsedDataResult else { throw MachOParseError.mmapFailed(error: "Parsing returned nil data") }

                // Update Status on MainActor (intermediate)
                await MainActor.run {
                    // Only update parser ref and status here, wait for final update for parsedData
                    self.currentParser = parser
                    self.statusMessage = self.generateSummary(for: parsedResult) + " Parsing dyld info..."
                    print("✅ Successfully parsed: \(binaryURL.lastPathComponent)")
                    if parsedResult.isEncrypted { print("⚠️ Binary is marked as encrypted.") }
                }


                // --- Step 1.5: Parse Dyld Info ---
                guard let currentParser = taskParser else { throw MachOParseError.mmapFailed(error: "Parser became nil unexpectedly") }
                do {
                    let dyldParser = try DyldInfoParser(parsedData: parsedResult)
                    taskDyldInfoResult = try dyldParser.parseAll()
                    print("✅ Successfully parsed dyld binding info.")
                } catch let error as DyldInfoParseError where error == .missingDyldInfoCommand {
                     print("ℹ️ Dyld info command not found.")
                } catch {
                     print("❌ Error parsing dyld binding info: \(error)")
                }
                 // Update Status on MainActor (intermediate)
                 await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting Swift..." }


                // --- Step 2a: Attempt Swift Extraction ---
                do {
                    let swiftExtractor = SwiftMetadataExtractor(parsedData: parsedResult, parser: currentParser)
                    taskSwiftMetaResult = try swiftExtractor.extract()
                    print("✅ Extracted Swift metadata (\(taskSwiftMetaResult?.types.count ?? 0) types).")
                } catch {
                    print("⚠️ Warning: Swift metadata extraction failed: \(error)")
                }
                 // Update Status on MainActor (intermediate)
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
                            // Assign results from local task variables to published properties
                            self.currentParser = taskParser
                            self.parsedData = taskParsedDataResult
                            self.parsedDyldInfo = taskDyldInfoResult
                            self.extractedSwiftTypes = taskSwiftMetaResult?.types ?? []

                            // ---- MOST EXPLICIT WAY TO HANDLE OBJ-C RESULTS ----
                            var finalClasses: [ObjCClass] = []
                            var finalProtocols: [ObjCProtocol] = []

                            if let objcMeta = taskObjCMetaResult {
                                // If we have metadata results, explicitly create Arrays from the values
                                finalClasses = Array(objcMeta.classes.values)
                                finalProtocols = Array(objcMeta.protocols.values)
                            }
                            // Assign the definitely-typed arrays and sort them
                            self.extractedClasses = finalClasses.sorted { $0.name < $1.name }
                            self.extractedProtocols = finalProtocols.sorted { $0.name < $1.name }
                            // ---- END EXPLICIT HANDLING ----


                            self.generatedHeader = taskHeaderTextResult
                            self.isLoading = false // Finish loading

                // Set final status and error messages based on outcomes
                if let error = taskErrorResult {
                    // Fatal error occurred
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.statusMessage = "Error processing file."
                    // Clear data if a fatal error occurred during parsing itself
                    if taskParsedDataResult == nil { self.parsedData = nil }

                } else if let objcError = taskObjCNotFoundErr {
                     // Only non-fatal "No ObjC Meta" occurred
                     self.errorMessage = objcError.localizedDescription
                     // Base status on the successfully parsed data
                     guard let pd = self.parsedData else {
                          self.statusMessage = "Error: State inconsistency."; return // Should not happen
                     }
                     var finalStatus = self.generateSummary(for: pd) + " No ObjC metadata."
                     // Check the already updated published property for Swift types
                     if !self.extractedSwiftTypes.isEmpty {
                         finalStatus += " Found \(self.extractedSwiftTypes.count) Swift types."
                     } else if taskSwiftMetaResult != nil { // Check if Swift extraction ran
                         finalStatus += " No Swift types found."
                     }
                     self.statusMessage = finalStatus

                 } else {
                    // Success path (parsing completed, ObjC meta might or might not exist but didn't error fatally)
                     self.errorMessage = nil
                                         guard let pd = self.parsedData else { self.statusMessage = "Error: State inconsistency."; return }
                                         var finalStatus = self.generateSummary(for: pd)
                                         // Use the already assigned properties here now
                                         if !self.extractedClasses.isEmpty { finalStatus += " Found \(self.extractedClasses.count) classes." }
                                         else if taskObjCMetaResult != nil { finalStatus += " No ObjC classes found." } // Check if extraction ran
                                         if !self.extractedSwiftTypes.isEmpty { finalStatus += " Found \(self.extractedSwiftTypes.count) Swift types."}
                                         else if taskSwiftMetaResult != nil { finalStatus += " No Swift types found." } // Check if extraction ran
                                         self.statusMessage = finalStatus.contains("Found") ? finalStatus : "Processing complete."
                                     }

                                     // Trigger UI update via counter
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


