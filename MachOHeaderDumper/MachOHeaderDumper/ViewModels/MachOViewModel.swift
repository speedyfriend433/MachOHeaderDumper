//
//  MachOViewModel.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: ViewModels/MachOViewModel.swift (Complete Code - Corrected Status Scoping)

import Foundation
import SwiftUI
import ObjCDump

@MainActor
class MachOViewModel: ObservableObject {

    // --- Input/State ---
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String = "Select a file to parse."
    @Published var showIvarsInHeader: Bool = false
    @Published var objcHeaderOutput: String? = nil
    @Published var swiftDumpOutput: String? = nil

    // --- Output Data ---
    @Published var parsedData: ParsedMachOData?
    @Published var parsedDyldInfo: ParsedDyldInfo?
    @Published var extractedClasses: [ObjCClass] = []
    @Published var extractedProtocols: [ObjCProtocol] = []
    @Published var extractedSwiftTypes: [SwiftTypeInfo] = []
    @Published var foundStrings: [FoundString] = []
    @Published var functionStarts: [FunctionStart] = []
    @Published var selectorReferences: [SelectorReference] = []
    @Published var extractedCategories: [ExtractedCategory] = [] // Added for categories
    @Published var generatedHeader: String?
    @Published var processingUpdateId = UUID()
    @Published var demanglerStatus: DemanglerStatus = .idle

    private var currentParser: MachOParser?

    // --- Main processing function ---
    func processURL(_ url: URL) {
        // Reset state immediately on MainActor
        self.isLoading = true
        self.errorMessage = nil
        self.parsedData = nil
        self.parsedDyldInfo = nil
        self.extractedClasses = []
        self.extractedProtocols = []
        self.extractedSwiftTypes = []
        self.foundStrings = []
        self.functionStarts = []
        self.selectorReferences = []
        self.extractedCategories = [] // Reset categories
        self.generatedHeader = nil
        self.demanglerStatus = .idle
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
                    self.currentParser = parser
                    self.statusMessage = self.generateSummary(for: parsedResult) + " Scanning strings..."
                    print("✅ Successfully parsed: \(binaryURL.lastPathComponent)")
                    if parsedResult.isEncrypted { print("⚠️ Binary is marked as encrypted.") }
                }

                // --- Step 1.1: Scan for Strings ---
                taskFoundStringsResult = StringScanner.scanForStrings(in: parsedResult)
                print("✅ Scanned for strings (\(taskFoundStringsResult?.count ?? 0) found).")
                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Parsing func starts..." }


                // --- Step 1.2: Parse Function Starts ---
                do { let addrs = try FunctionStartsParser.parseFunctionStarts(in: parsedResult); taskFunctionStartsResult = addrs.map { FunctionStart(address: $0) }; print("✅ Parsed \(taskFunctionStartsResult?.count ?? 0) function starts.") }
                catch let error as FunctionStartsParseError where error == .commandNotFound { print("ℹ️ LC_FUNCTION_STARTS not found."); taskFunctionStartsResult = [] }
                catch { print("❌ Error parsing function starts: \(error)"); taskFunctionStartsResult = nil }
                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Lookup demangler..." }


                // --- Step 1.3: Lookup Demangler ---
                let lookupResult = DynamicSymbolLookup.getSwiftDemangleFunctionPointer(forBinaryPath: binaryURL.path)
                taskDemanglerFunc = lookupResult.function
                taskDemanglerStatus = lookupResult.status
                // Status updated in final block


                // --- Step 1.5: Parse Dyld Info ---
                guard let currentParser = taskParser else { throw MachOParseError.mmapFailed(error: "Parser became nil unexpectedly") }
                do { let dyldParser = try DyldInfoParser(parsedData: parsedResult); taskDyldInfoResult = try dyldParser.parseAll(); print("✅ Successfully parsed dyld info.") }
                catch let error as DyldInfoParseError where error == .missingDyldInfoCommand { print("ℹ️ Dyld info command not found.") }
                catch { print("❌ Error parsing dyld info: \(error)") }
                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting Swift..." }


                // --- Step 2a: Attempt Swift Extraction ---
                let swiftTypesSectionExists = parsedResult.loadCommands.contains { c in if case .segment64(let s, let sects) = c { return stringFromCChar16Tuple(s.segname) == "__TEXT" && sects.contains { $0.name == "__swift5_types" } } else { return false } }
                if swiftTypesSectionExists {
                    do { let extr = SwiftMetadataExtractor(parsedData: parsedResult, parser: currentParser, demanglerFunc: taskDemanglerFunc); taskSwiftMetaResult = try extr.extract(); print("✅ Extracted Swift (\(taskSwiftMetaResult?.types.count ?? 0) types).") }
                     catch { print("⚠️ Swift extraction failed: \(error)") }
                 } else { if taskDemanglerStatus == .idle { taskDemanglerStatus = .notAttempted }; print("ℹ️ No Swift sections found.") }
                 await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting ObjC..." }


                // --- Step 2b: Attempt ObjC Extraction ---
                do { let extr = ObjCMetadataExtractor(parsedData: parsedResult, parser: currentParser); taskObjCMetaResult = try await extr.extract(); print("✅ Extracted ObjC.") }
                catch let error as MachOParseError where error == .noObjectiveCMetadataFound { print("ℹ️ No ObjC metadata found."); taskObjCNotFoundErr = error }
                catch { throw error }


                // --- Step 3: Generate Header ---
                if let validObjCMeta = taskObjCMetaResult { let gen = HeaderGenerator(metadata: validObjCMeta); let ivars = await MainActor.run { self.showIvarsInHeader }; taskHeaderTextResult = try await gen.generateHeader(includeIvarsInHeader: ivars); print("✅ Generated ObjC header.") }

            } catch { // Catch outer fatal errors
                taskErrorResult = error
                print("❌ Error during processing: \(error)")
            }

            // --- Final Update on MainActor ---
            await MainActor.run {
                // Assign all results collected in background
                self.currentParser = taskParser
                self.parsedData = taskParsedDataResult
                self.parsedDyldInfo = taskDyldInfoResult
                self.extractedSwiftTypes = taskSwiftMetaResult?.types ?? []
                self.foundStrings = taskFoundStringsResult ?? []
                self.functionStarts = taskFunctionStartsResult ?? []

                // Explicit ObjC array handling
                var finalClasses: [ObjCClass] = []
                var finalProtocols: [ObjCProtocol] = []
                var finalSelRefs: [SelectorReference] = []
                var finalCategories: [ExtractedCategory] = [] // Added
                if let objcMeta = taskObjCMetaResult {
                    finalClasses = Array(objcMeta.classes.values)
                    finalProtocols = Array(objcMeta.protocols.values)
                    finalSelRefs = objcMeta.selectorReferences
                    finalCategories = objcMeta.categories // Added
                }
                self.extractedClasses = finalClasses.sorted { $0.name < $1.name }
                self.extractedProtocols = finalProtocols.sorted { $0.name < $1.name }
                self.selectorReferences = finalSelRefs // Assign SelRefs
                self.extractedCategories = finalCategories // Assign Categories

                self.generatedHeader = taskHeaderTextResult
                self.demanglerStatus = taskDemanglerStatus

                self.isLoading = false // Finish loading

                // --- CORRECTED Status/Error Logic ---
                // Declare finalStatus variable *before* the if/else block
                var finalStatus = ""
                guard let pd = self.parsedData else {
                    // This should only happen if parsing itself failed fatally
                    self.errorMessage = taskErrorResult?.localizedDescription ?? "Unknown parsing error."
                    self.statusMessage = "Error during initial parsing."
                    self.processingUpdateId = UUID(); // Trigger update
                    return // Exit early
                }

                // Start building status string
                finalStatus = self.generateSummary(for: pd)

                // Set error/status based on outcomes
                if let error = taskErrorResult {
                    // Fatal error occurred after successful parsing
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    finalStatus += " Error occurred." // Append to base summary
                } else if let objcError = taskObjCNotFoundErr {
                    // Only non-fatal "No ObjC Meta" occurred
                    self.errorMessage = objcError.localizedDescription // Show as non-fatal info/warning
                    finalStatus += " No ObjC metadata." // Append info
                    // Add other counts if available
                    if !self.extractedSwiftTypes.isEmpty { finalStatus += " Found \(self.extractedSwiftTypes.count) Swift types." }
                    if !self.foundStrings.isEmpty { finalStatus += " \(self.foundStrings.count) Strs."}
                    if !self.functionStarts.isEmpty { finalStatus += " \(self.functionStarts.count) Funcs."}
                    if !self.selectorReferences.isEmpty { finalStatus += " \(self.selectorReferences.count) SelRefs."} // SelRefs *can* exist without classes
                 } else {
                    // Success path (parsing completed, no fatal errors, ObjC extraction didn't throw missing sections)
                    self.errorMessage = nil // Clear previous errors
                    var foundItems = false // Track if anything interesting was found

                    // Append counts for found items
                    if !self.extractedClasses.isEmpty || !self.extractedProtocols.isEmpty {
                        finalStatus += " Found \(self.extractedClasses.count) Cls, \(self.extractedProtocols.count) Proto."
                        foundItems = true
                    } else if taskObjCMetaResult != nil { // ObjC ran but found no interfaces
                        finalStatus += " No ObjC interfaces."
                    }
                    // Only mention categories if classes/protocols weren't the primary find
                    if !self.extractedCategories.isEmpty && self.extractedClasses.isEmpty && self.extractedProtocols.isEmpty {
                         finalStatus += " Found \(self.extractedCategories.count) Cats."
                         foundItems = true
                    }
                    if !self.selectorReferences.isEmpty {
                        finalStatus += " \(self.selectorReferences.count) SelRefs."
                        // Consider selrefs less "interesting" than classes/protocols/swift for foundItems flag? Maybe.
                        if !foundItems { foundItems = true }
                    }
                    if !self.extractedSwiftTypes.isEmpty {
                         finalStatus += " Found \(self.extractedSwiftTypes.count) Swift types."
                         foundItems = true
                    } else if taskSwiftMetaResult != nil {
                         finalStatus += " No Swift types."
                    }
                    if !self.foundStrings.isEmpty { finalStatus += " \(self.foundStrings.count) Strs."}
                    if !self.functionStarts.isEmpty { finalStatus += " \(self.functionStarts.count) Funcs."}

                    // Adjust final message if nothing specific was found
                    if !foundItems && taskObjCMetaResult != nil && taskSwiftMetaResult != nil {
                        finalStatus = self.generateSummary(for: pd) + " Processed. No specific interfaces/types found."
                    } else if !finalStatus.contains("Found") {
                         // Fallback if somehow no counts were added but no error occurred
                         finalStatus = self.generateSummary(for: pd) + " Processing complete."
                    }
                }
                // Assign the constructed status message
                self.statusMessage = finalStatus
                // --- END CORRECTED STATUS/ERROR ---


                // Trigger UI update
                print("ViewModel: Publishing final update ID.") // Debug log
                self.processingUpdateId = UUID()

            } // End MainActor.run
        } // End Task.detached
    } // End processURL

    // --- Helper Functions ---

    // Should remain nonisolated
    private nonisolated func resolveBinaryPath(for url: URL) throws -> URL {

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


