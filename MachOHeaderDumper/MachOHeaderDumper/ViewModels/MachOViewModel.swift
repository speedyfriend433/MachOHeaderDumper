//
//  MachOViewModel.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: MachOViewModel.swift (Add Update Counter)

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

    // --- ADDED: Counter to trigger consolidated onChange ---
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
            var taskSwiftMetaResult: ExtractedSwiftMetadata? = nil // Renamed for clarity
            var taskObjCMetaResult: ExtractedMetadata? = nil // Renamed for clarity
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

                // Update status and store parser on MainActor
                await MainActor.run {
                    self.parsedData = parsedResult
                    self.currentParser = parser // Store after successful parse
                    self.statusMessage = self.generateSummary(for: parsedResult) + " Parsing dyld info..."
                    print("✅ Successfully parsed: \(binaryURL.lastPathComponent)")
                    if parsedResult.isEncrypted { print("⚠️ Binary is marked as encrypted.") }
                }

                // --- Step 1.5: Parse Dyld Info ---
                // Re-get parser instance safely on background if needed, or assume it's valid
                // For simplicity, assume currentParser is valid if we reached here
                guard let currentParser = taskParser else { throw MachOParseError.mmapFailed(error: "Parser became nil unexpectedly") }
                do {
                    let dyldParser = try DyldInfoParser(parsedData: parsedResult)
                    taskDyldInfoResult = try dyldParser.parseAll()
                    print("✅ Successfully parsed dyld binding info.")
                } catch let error as DyldInfoParseError where error == .missingDyldInfoCommand {
                     print("ℹ️ Dyld info command not found, skipping binding analysis.")
                } catch {
                     print("❌ Error parsing dyld binding info: \(error)")
                }
                // Update status (dispatch back to main)
                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting Swift..." }

                // --- Step 2a: Attempt Swift Extraction ---
                do {
                    let swiftExtractor = SwiftMetadataExtractor(parsedData: parsedResult, parser: currentParser)
                    taskSwiftMetaResult = try swiftExtractor.extract() // Assign to local task variable
                    print("✅ Extracted Swift metadata (\(taskSwiftMetaResult?.types.count ?? 0) types).")
                } catch {
                    print("⚠️ Warning: Swift metadata extraction failed: \(error)")
                }
                 // Update status (dispatch back to main)
                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting ObjC..." }


                // --- Step 2b: Attempt ObjC Extraction ---
                do {
                    let extractor = ObjCMetadataExtractor(parsedData: parsedResult, parser: currentParser)
                    taskObjCMetaResult = try await extractor.extract() // Assign to local task variable
                    print("✅ Successfully extracted ObjC metadata.")
                } catch let error as MachOParseError where error == .noObjectiveCMetadataFound {
                    print("ℹ️ No Objective-C metadata found.")
                    taskObjCNotFoundErr = error // Store specific error locally
                } catch {
                    // Rethrow other critical ObjC extraction errors
                    throw error
                }

                // --- Step 3: Generate Header (ObjC only for now) ---
                if let validObjCMeta = taskObjCMetaResult {
                    let headerGenerator = HeaderGenerator(metadata: validObjCMeta)
                    let includeIvars = await MainActor.run { self.showIvarsInHeader }
                    taskHeaderTextResult = try await headerGenerator.generateHeader(includeIvarsInHeader: includeIvars) // Assign to local task variable
                    print("✅ Successfully generated ObjC header.")
                }

            } catch { // Catch outer errors
                taskErrorResult = error
                print("❌ Error during processing: \(error)")
            }

            // --- Final Update on MainActor ---
            await MainActor.run {
                // Assign results from local task variables to published properties
                // self.currentParser is already set if parse succeeded
                self.parsedData = taskParsedDataResult
                self.parsedDyldInfo = taskDyldInfoResult
                // FIX: Correctly reference taskSwiftMetaResult
                self.extractedSwiftTypes = taskSwiftMetaResult?.types ?? []
                // FIX: Correctly handle optional Values collection and reference taskObjCMetaResult
                // FIX: Use map to get array from optional dictionary values
                    let classesArray: [ObjCClass] = taskObjCMetaResult?.classes.values.map { $0 } ?? []
                    self.extractedClasses = classesArray.sorted { $0.name < $1.name }

                    let protocolsArray: [ObjCProtocol] = taskObjCMetaResult?.protocols.values.map { $0 } ?? []
                    self.extractedProtocols = protocolsArray.sorted { $0.name < $1.name }
                self.generatedHeader = taskHeaderTextResult

                self.isLoading = false // Finish loading
                // --- ADDED: Increment update counter ---
                                // This signals that all data updates are complete for this run
                                self.processingUpdateId = UUID()

                // Determine final status and error messages
                if let error = taskErrorResult {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.statusMessage = "Error processing file."
                    // Clear parsedData only if the initial parse failed
                    if taskParsedDataResult == nil { self.parsedData = nil }

                } else if let objcError = taskObjCNotFoundErr { // FIX: Reference taskObjCNotFoundErr correctly
                     self.errorMessage = objcError.localizedDescription
                     // Use non-optional self.parsedData as parsing must have succeeded to reach here
                     var finalStatus = self.generateSummary(for: self.parsedData!)
                     finalStatus += " No ObjC metadata."
                     // FIX: Correctly reference taskSwiftMetaResult for Swift count
                     if let swiftMeta = taskSwiftMetaResult, !swiftMeta.types.isEmpty {
                         finalStatus += " Found \(swiftMeta.types.count) Swift types."
                     } else if taskSwiftMetaResult != nil { // Check if Swift extraction ran but found none
                         finalStatus += " No Swift types found."
                     }
                     self.statusMessage = finalStatus

                 } else {
                    // Success path
                    self.errorMessage = nil
                    var finalStatus = self.generateSummary(for: self.parsedData!)
                    // FIX: Check taskObjCMetaResult for ObjC info
                    if let objcMeta = taskObjCMetaResult, !objcMeta.classes.isEmpty {
                        finalStatus += " Found \(objcMeta.classes.count) classes."
                    } else if taskObjCMetaResult != nil { // Check if ObjC extraction ran but found none
                        finalStatus += " No ObjC classes found."
                    }
                    // FIX: Check taskSwiftMetaResult for Swift info
                    if let swiftMeta = taskSwiftMetaResult, !swiftMeta.types.isEmpty {
                         finalStatus += " Found \(swiftMeta.types.count) Swift types."
                    } else if taskSwiftMetaResult != nil { // Check if Swift extraction ran but found none
                         finalStatus += " No Swift types found."
                    }
                    self.statusMessage = finalStatus.contains("Found") ? finalStatus : "Processing complete. No specific data extracted."
                }
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


