//
//  MachOViewModel.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation
import SwiftUI
// import SwiftDemangle

@MainActor
class MachOViewModel: ObservableObject {

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String = "Select a file to parse."
    @Published var showIvarsInHeader: Bool = false
    @Published var parsedData: ParsedMachOData?
    @Published var parsedDyldInfo: ParsedDyldInfo?
    @Published var foundStrings: [FoundString] = []
    @Published var functionStarts: [FunctionStart] = []
    @Published var extractedClasses: [ObjCClass] = []
    @Published var extractedProtocols: [ObjCProtocol] = []
    @Published var extractedCategories: [ExtractedCategory] = []
    @Published var selectorReferences: [SelectorReference] = []
    @Published var extractedSwiftTypes: [SwiftTypeInfo] = []
    @Published var generatedHeader: String?
    @Published var processingUpdateId = UUID()

    private var currentParser: MachOParser?

    func processURL(_ url: URL) {
        self.isLoading = true
        self.errorMessage = nil
        self.parsedData = nil
        self.parsedDyldInfo = nil
        self.foundStrings = []
        self.functionStarts = []
        self.extractedClasses = []
        self.extractedProtocols = []
        self.extractedCategories = []
        self.selectorReferences = []
        self.extractedSwiftTypes = []
        self.generatedHeader = nil
        self.statusMessage = "Processing \(url.lastPathComponent)..."
        self.currentParser = nil
        
        Task.detached(priority: .userInitiated) {
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
            
            do {
                let binaryURL = try self.resolveBinaryPath(for: url)
                await MainActor.run { self.statusMessage = "Parsing \(binaryURL.lastPathComponent)..." }
                
                // --- Step 1: Parse Mach-O Structure ---
                taskParser = MachOParser(fileURL: binaryURL)
                guard let parser = taskParser else { throw MachOParseError.mmapFailed(error: "Failed to initialize parser") }
                taskParsedDataResult = try await Task { try parser.parse() }.value
                guard let parsedResult = taskParsedDataResult else { throw MachOParseError.mmapFailed(error: "Parsing returned nil data") }
                await MainActor.run { self.currentParser = parser; self.statusMessage = self.generateSummary(for: parsedResult) + " Scanning..." }
                
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { taskFoundStringsResult = StringScanner.scanForStrings(in: parsedResult) }
                    group.addTask { do { let addrs = try FunctionStartsParser.parseFunctionStarts(in: parsedResult); taskFunctionStartsResult = addrs.map { FunctionStart(address: $0) } } catch { print("Func starts failed: \(error)") } }
                    group.addTask { do { let dyldParser = try DyldInfoParser(parsedData: parsedResult); taskDyldInfoResult = try dyldParser.parseAll() } catch { print("Dyld info failed: \(error)") } }
                }
                print("✅ Scanned Strings, Func Starts, Dyld Info.")
                await MainActor.run { self.statusMessage = self.generateSummary(for: parsedResult) + " Extracting..." }
                
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let swiftTypesSectionExists = parsedResult.loadCommands.contains { c in if case .segment64(let s, let sects) = c { return stringFromCChar16Tuple(s.segname) == "__TEXT" && sects.contains { $0.name == "__swift5_types" } } else { return false } }
                        if swiftTypesSectionExists {
                            do {
                                let swiftExtractor = SwiftMetadataExtractor(parsedData: parsedResult, parser: parser)
                                taskSwiftMetaResult = try swiftExtractor.extract()
                                print("✅ Extracted Swift metadata.")
                            } catch { print("⚠️ Swift extraction failed: \(error)") }
                        } else { print("ℹ️ No Swift sections found.") }
                    }
                    group.addTask {
                        do {
                            let extractor = ObjCMetadataExtractor(parsedData: parsedResult, parser: parser)
                            taskObjCMetaResult = try await extractor.extract()
                            print("✅ Extracted ObjC metadata.")
                        } catch let error as MachOParseError where error == .noObjectiveCMetadataFound {
                            print("ℹ️ No ObjC metadata found.")
                            taskObjCNotFoundErr = error
                        } catch {
                            print("❌ Critical ObjC extraction error: \(error)")
                            taskErrorResult = error
                        }
                    }
                }
                
                if let validObjCMeta = taskObjCMetaResult {
                    let headerGenerator = HeaderGenerator(metadata: validObjCMeta)
                    let includeIvars = await MainActor.run { self.showIvarsInHeader }
                    taskHeaderTextResult = try await headerGenerator.generateHeader(includeIvarsInHeader: includeIvars)
                    print("✅ Generated ObjC header.")
                }
                
            } catch {
                taskErrorResult = error
                print("❌ Error during processing: \(error)")
            }
            
            await MainActor.run {
                            self.currentParser = taskParser
                            self.parsedData = taskParsedDataResult
                            self.parsedDyldInfo = taskDyldInfoResult
                            self.extractedSwiftTypes = taskSwiftMetaResult?.types ?? []
                            self.foundStrings = taskFoundStringsResult ?? []
                            self.functionStarts = taskFunctionStartsResult ?? []

                            if let objcMeta = taskObjCMetaResult {
                                self.extractedClasses = Array(objcMeta.classes.values).sorted { $0.name < $1.name }
                                self.extractedProtocols = Array(objcMeta.protocols.values).sorted { $0.name < $1.name }
                                self.extractedCategories = objcMeta.categories
                                self.selectorReferences = objcMeta.selectorReferences
                            } else {
                                self.extractedClasses = []
                                self.extractedProtocols = []
                                self.extractedCategories = []
                                self.selectorReferences = []
                            }
                            self.generatedHeader = taskHeaderTextResult
                            self.isLoading = false

                    if let error = taskErrorResult {
                        self.errorMessage = "Error: \(error.localizedDescription)"
                        self.statusMessage = "Error processing file."
                    } else {
                        self.errorMessage = taskObjCNotFoundErr?.localizedDescription
                        guard let pd = self.parsedData else { return }
                        var statusParts: [String] = [self.generateSummary(for: pd)]
                        var foundObjCContent = false
                        
                        if !self.extractedClasses.isEmpty {
                            statusParts.append("Dumped \(self.extractedClasses.count) Cls.")
                            foundObjCContent = true
                        }
                        if !self.extractedProtocols.isEmpty {
                            statusParts.append("Dumped \(self.extractedProtocols.count) Proto.")
                            foundObjCContent = true
                        }
                        if !self.extractedCategories.isEmpty {
                            statusParts.append("Dumped \(self.extractedCategories.count) Cats.")
                            foundObjCContent = true
                        }
                        if !foundObjCContent && taskObjCMetaResult != nil && taskObjCNotFoundErr == nil {
                            statusParts.append("No ObjC interfaces.")
                        } else if taskObjCNotFoundErr != nil {
                            statusParts.append("No ObjC metadata.")
                        }
                        if self.generatedHeader?.contains("No Objective-C interfaces") ?? false {
                            self.generatedHeader = nil
                        }
                    }
                self.processingUpdateId = UUID()
            }
        }
    }

    private nonisolated func resolveBinaryPath(for url: URL) throws -> URL {
        
        var isDirectory: ObjCBool = false;
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return url };
        let fm = FileManager.default;
        let ext = url.pathExtension.lowercased();
        if ext == "app" || ext == "framework" {
            let infoURL = url.appendingPathComponent("Info.plist");
            guard fm.fileExists(atPath: infoURL.path)
            else {
                let defName = url.deletingPathExtension().lastPathComponent;
                let binURL = url.appendingPathComponent(defName);
                return fm.fileExists(atPath: binURL.path) ? binURL : url };
            do {
                let data = try Data(contentsOf: infoURL);
                if
                    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String:Any],
                    let exec = plist["CFBundleExecutable"] as? String {
                    let binURL = url.appendingPathComponent(exec);
                    if fm.fileExists(atPath: binURL.path) {
                        return binURL }
                    else { throw MachOParseError.fileNotFound(path: binURL.path) } }
                else {
                    let defName = url.deletingPathExtension().lastPathComponent;
                    let binURL = url.appendingPathComponent(defName);
                    return fm.fileExists(atPath: binURL.path) ? binURL : url } }
            catch {
                return url } }
        else {
            return url }
    }

    private func generateSummary(for data: ParsedMachOData) -> String {
        let arch = cpuTypeToString(data.header.cputype)
        let encryptedStatus = data.isEncrypted ? " (Encrypted)" : ""
        return "Parsed \(arch)\(encryptedStatus)."
     }
}



