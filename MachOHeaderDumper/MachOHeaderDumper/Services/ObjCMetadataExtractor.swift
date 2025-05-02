//
//  ObjCMetadataExtractor.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

// File: Services/ObjCMetadataExtractor.swift (Complete - Two-Pass, Entsize, Logging)

import Foundation
import MachO

class ObjCMetadataExtractor {
    private let parsedData: ParsedMachOData
    private let parser: MachOParser

    private var sectionCache: [String: ParsedSection] = [:]
    private var metaClassROCache: [UInt64: class_ro_t] = [:]
    private var classCacheByAddress: [UInt64: ObjCClass] = [:] 

    init(parsedData: ParsedMachOData, parser: MachOParser) {
        self.parsedData = parsedData
        self.parser = parser
    }

    /// Main extraction entry point. Performs two passes.
    func extract() async throws -> ExtractedMetadata {
        print("ℹ️ ObjCMetadataExtractor: Starting extraction...")
        // Reset caches for each run
        metaClassROCache.removeAll()
        classCacheByAddress.removeAll()
        sectionCache.removeAll() // Re-cache sections each time

        var metadata = ExtractedMetadata() // Final result container

        // Ensure required sections are mapped for quick lookup
        try cacheRequiredSections()

        // --- PASS 1: Extract base info, cache classes, store categories ---
        print("ℹ️ ObjCMetadataExtractor: Starting Pass 1...")
        try extractProtocols(into: &metadata) // Protocols stored directly in metadata
        try extractClassesAndCategoriesPass1(into: &metadata) // Populates classCacheByAddress & metadata.categories
        print("ℹ️ ObjCMetadataExtractor: Pass 1 finished. Cached Classes: \(classCacheByAddress.count), Found Categories: \(metadata.categories.count)")


        // --- PASS 2: Resolve hierarchy, read details, merge categories ---
        print("ℹ️ ObjCMetadataExtractor: Starting Pass 2...")
        try resolveHierarchyAndClassData(processing: &metadata) // Modifies cached classes, merges categories
        print("ℹ️ ObjCMetadataExtractor: Pass 2 finished.")


        // --- Final Steps ---
        try extractSelectorReferences(into: &metadata) // Parse selector references

        // --- FINAL ASSEMBLY: Move from cache to final metadata struct ---
        print("ℹ️ ObjCMetadataExtractor: Assembling final results...")
        for (_, cls) in classCacheByAddress {
            if metadata.classes[cls.name] == nil {
                 metadata.classes[cls.name] = cls
            } else {
                 print("Warning: Duplicate class name '\(cls.name)' encountered during final assembly.")
                 // Optionally merge properties/methods if duplicates found? For now, keep first.
            }
        }
        // Clear temporary caches
        classCacheByAddress.removeAll()
        metaClassROCache.removeAll()

        print("ℹ️ ObjCMetadataExtractor: Extraction finished. Final Counts - Classes: \(metadata.classes.count), Protocols: \(metadata.protocols.count), Categories: \(metadata.categories.count), SelRefs: \(metadata.selectorReferences.count)")
        return metadata
    }
    
    // Helper to check if any relevant sections were found
        private func didFindObjCSections() -> Bool {
            return sectionCache["__objc_classlist"] != nil ||
                   sectionCache["__objc_protolist"] != nil ||
                   sectionCache["__objc_catlist"] != nil ||
                   sectionCache["__objc_const"] != nil
        }

    // MARK: - Section Caching
        private func cacheRequiredSections() throws {
            // Define sections needed for ObjC analysis
            let required = [
                // Lists
                ("__DATA_CONST", "__objc_classlist"), ("__DATA", "__objc_classlist"),
                ("__DATA_CONST", "__objc_protolist"), ("__DATA", "__objc_protolist"),
                ("__DATA_CONST", "__objc_catlist"), ("__DATA", "__objc_catlist"),
                ("__DATA_CONST", "__objc_selrefs"), ("__DATA", "__objc_selrefs"),
                // Data Sections
                ("__DATA_CONST", "__objc_const"), // Read-only class data (class_ro_t)
                ("__TEXT", "__objc_classname"),   // Class name strings
                ("__TEXT", "__objc_methname"),  // Selector name strings
                ("__TEXT", "__objc_methtype"),  // Method type encoding strings
                 // Add others if needed later (e.g., __objc_ivar, __objc_superrefs)
            ]
            print("  [Debug] cacheRequiredSections: Caching sections...")
            var foundKeys: Set<String> = []
            for (seg, sect) in required {
                if let section = parsedData.section(segmentName: seg, sectionName: sect) {
                    sectionCache["\(seg)/\(sect)"] = section
                    // Store under the generic section name key if not already present
                    if sectionCache[sect] == nil {
                         sectionCache[sect] = section
                         print("    [Debug] cacheRequiredSections: Found \(sect) in \(seg) at offset \(section.command.offset)")
                         foundKeys.insert(sect) // Track found generic keys
                    } else {
                         // Found in alternate segment, maybe log?
                         // print("    [Debug] cacheRequiredSections: Found alternate location for \(sect) in \(seg)")
                    }
                }
            }
            print("  [Debug] cacheRequiredSections: Caching complete. Found primary keys: \(foundKeys.sorted())")

            // Add essential checks - if these fail, extraction likely impossible
            guard sectionCache["__objc_methname"] != nil, sectionCache["__objc_methtype"] != nil else {
                 throw MachOParseError.sectionNotFound(segment: "__TEXT", section: "__objc_methname/__objc_methtype")
            }
            // Note: We don't *require* classlist/protolist/catlist etc. to exist, the methods handle nil lookups.
            // However, if classlist *is* present, we *need* __objc_const and __objc_classname
             if sectionCache["__objc_classlist"] != nil {
                 guard sectionCache["__objc_const"] != nil else { throw MachOParseError.sectionNotFound(segment:"__DATA_CONST", section: "__objc_const") }
                 guard sectionCache["__objc_classname"] != nil else { throw MachOParseError.sectionNotFound(segment:"__TEXT", section: "__objc_classname") }
             }
        }

        /// Helper to safely get a cached section.
        private func getSection(_ name: String) -> ParsedSection? {
            return sectionCache[name] // Returns nil if not found
        }

    // MARK: - Extraction Logic

        private func extractProtocols(into metadata: inout ExtractedMetadata) throws {
            guard let protoListSection = getSection("__objc_protolist") else {
                print("ℹ️ ObjCMetadataExtractor: __objc_protolist section not found.")
                return
            }
            let sectionFileOffset = UInt64(protoListSection.command.offset)
            let sectionSize = protoListSection.command.size
            let pointerCount = Int(sectionSize) / POINTER_SIZE
            print("ℹ️ ObjCMetadataExtractor: Parsing __objc_protolist section (\(pointerCount) potential entries)...")


            for i in 0..<pointerCount {
                let pointerOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
                 guard pointerOffset + UInt64(POINTER_SIZE) <= parsedData.dataRegion.count else { break } // Bounds check
                let protocolVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(pointerOffset))
                guard protocolVMPtr != 0 else { continue }

                do {
                    if let proto = try readProtocol(at: protocolVMPtr) {
                        if metadata.protocols[proto.name] == nil { metadata.protocols[proto.name] = proto }
                    }
                } catch let error as MachOParseError {
                    print("Warning: Failed to read protocol at VM address 0x\(String(protocolVMPtr, radix: 16)): \(error.localizedDescription)")
                }
            }
        }
    
    // Pass 1: Extracts base info, caches classes by address, stores categories in metadata
        private func extractClassesAndCategoriesPass1(into metadata: inout ExtractedMetadata) throws {
            // --- Class Extraction ---
            if let classListSection = getSection("__objc_classlist") {
                let sectionFileOffset = UInt64(classListSection.command.offset)
                let sectionSize = classListSection.command.size
                let pointerCount = Int(sectionSize) / POINTER_SIZE
                 print("ℹ️ ObjCMetadataExtractor: Parsing __objc_classlist section (\(pointerCount) potential entries)...")

                for i in 0..<pointerCount {
                     let pointerOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
                     guard pointerOffset + UInt64(POINTER_SIZE) <= parsedData.dataRegion.count else { break }
                     let classVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(pointerOffset))
                     guard classVMPtr != 0 else { continue }

                     do {
                         let roVMPtr = try resolveRODataPtr(fromClassPtr: classVMPtr)
                         guard roVMPtr != 0 else { print("    [Debug] Pass 1: Skipping class 0x\(String(classVMPtr, radix: 16)), could not resolve RO ptr."); continue }
                         // Read base info (name, flags, superclass ptr) and cache
                         try readClassBaseInfo(roPointer: roVMPtr, classVMAddress: classVMPtr)
                     } catch {
                         print("Warning: Pass 1: Failed processing class ptr 0x\(String(classVMPtr, radix: 16)): \(error)")
                     }
                }
            } else {
                 print("ℹ️ ObjCMetadataExtractor: __objc_classlist section not found.")
            }
            
            // --- Category Extraction ---
                    if let catListSection = getSection("__objc_catlist") {
                        let sectionFileOffset = UInt64(catListSection.command.offset)
                        let sectionSize = catListSection.command.size
                        let pointerCount = Int(sectionSize) / POINTER_SIZE
                        print("ℹ️ ObjCMetadataExtractor: Parsing __objc_catlist section (\(pointerCount) potential entries)...")

                        for i in 0..<pointerCount {
                             let pointerOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
                             guard pointerOffset + UInt64(POINTER_SIZE) <= parsedData.dataRegion.count else { break }
                             let categoryVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(pointerOffset))
                             guard categoryVMPtr != 0 else { continue }
                             do {
                                 // Reads category details and stores in metadata.categories with temp target ptr
                                 try readCategoryInfo(categoryVMPtr: categoryVMPtr, into: &metadata)
                             } catch {
                                  print("Warning: Pass 1: Failed processing category ptr 0x\(String(categoryVMPtr, radix: 16)): \(error)")
                             }
                        }
                    } else {
                         print("ℹ️ ObjCMetadataExtractor: __objc_catlist section not found.")
                    }
                }
    
    
    // Pass 1 Helper: Reads only base info and populates classCacheByAddress
        private func readClassBaseInfo(roPointer: UInt64, classVMAddress: UInt64) throws {
             guard classCacheByAddress[classVMAddress] == nil else { return } // Avoid re-processing

             let roFileOffset = try parser.fileOffset(for: roPointer, parsedData: parsedData)
             // Bounds check before reading class_ro_t
             guard roFileOffset + UInt64(MemoryLayout<class_ro_t>.stride) <= parsedData.dataRegion.count else {
                 print("Warning: readClassBaseInfo - Read out of bounds for class_ro_t at offset \(roFileOffset)")
                 return
             }
             let roData: class_ro_t = try parsedData.dataRegion.read(at: Int(roFileOffset))

             guard let name = try readString(atVMAddress: roData.name) else { return }
             print("    [Debug] Pass 1: Processing Class = \(name) (VM: 0x\(String(classVMAddress, radix: 16)), RO: 0x\(String(roPointer, radix: 16)))")

             // Read superclass pointer from class struct
             var superclassPtr: UInt64 = 0
             if classVMAddress != 0 {
                 do {
                     let superclassPtrAddr = classVMAddress + 0x8 // Usual offset for superclass field
                     let superclassPtrFileOffset = try parser.fileOffset(for: superclassPtrAddr, parsedData: parsedData)
                     guard superclassPtrFileOffset + UInt64(POINTER_SIZE) <= parsedData.dataRegion.count else { throw MachOParseError.dataReadOutOfBounds(offset: Int(superclassPtrFileOffset), length: POINTER_SIZE, totalSize: parsedData.dataRegion.count) }
                     superclassPtr = try parsedData.dataRegion.read(at: Int(superclassPtrFileOffset))
                 } catch { print("    [Debug] Pass 1: Failed read superclass ptr for \(name): \(error)") }
             }

             let isSwift = roData.isSwiftClass // Use helper from struct
             if isSwift { print("    [Debug] Pass 1: Detected Swift flag for \(name)") }

             let cls = ObjCClass(name: name, vmAddress: classVMAddress, isSwift: isSwift)
             cls.setTemporarySuperclassPointer(superclassPtr) // Store pointer for Pass 2

             classCacheByAddress[classVMAddress] = cls // Add to cache
         }

        // Pass 1 Helper: Reads category info and stores in metadata.categories
        private func readCategoryInfo(categoryVMPtr: UInt64, into metadata: inout ExtractedMetadata) throws {
            let catFileOffset = try parser.fileOffset(for: categoryVMPtr, parsedData: parsedData)
            // Bounds check before reading category_t
            guard catFileOffset + UInt64(MemoryLayout<category_t>.stride) <= parsedData.dataRegion.count else {
                 print("Warning: readCategoryInfo - Read out of bounds for category_t at offset \(catFileOffset)")
                 return
            }
            let catData: category_t = try parsedData.dataRegion.read(at: Int(catFileOffset))

            guard let catName = try readString(atVMAddress: catData.name) else { return }
            let targetClassPtr = catData.classRef
            guard targetClassPtr != 0 else { return }

            print("    [Debug] Pass 1: Processing Category = \(catName) (Target Ptr: 0x\(String(targetClassPtr, radix: 16)))")

            var category = ExtractedCategory(name: catName, className: "<Resolving>") // Placeholder
            category.setTemporaryTargetClassPointer(targetClassPtr)

            // Read lists associated with the category now
            category.instanceMethods = try readMethodList(atVMAddress: catData.instanceMethods, isClassMethod: false)
            category.classMethods = try readMethodList(atVMAddress: catData.classMethods, isClassMethod: true)
            category.protocols = try readProtocolListNames(atVMAddress: catData.protocols)
            category.instanceProperties = try readPropertyList(atVMAddress: catData.instanceProperties)
            // Assume category_t has no classProperties field for now

            metadata.categories.append(category)
         }
    
    // MARK: - Pass 2 Methods

        // Pass 2: Iterates cached classes, resolves hierarchy, reads details, merges categories
        private func resolveHierarchyAndClassData(processing metadata: inout ExtractedMetadata) throws {
             print("ℹ️ ObjCMetadataExtractor: Starting Pass 2: Resolving hierarchy and details...")
             let allClassAddresses = Array(classCacheByAddress.keys) // Get addresses to process

             // Resolve hierarchy for all cached classes first
             for classAddr in allClassAddresses {
                 guard let cls = classCacheByAddress[classAddr] else { continue }
                 resolveClassHierarchy(cls: cls) // Resolve superclass name
             }

            // Now read full data and resolve/merge categories
             for classAddr in allClassAddresses {
                 guard let cls = classCacheByAddress[classAddr] else { continue }

                 // Read Full Instance Data
                 do {
                      let roPtr = try resolveRODataPtr(fromClassPtr: classAddr)
                      if roPtr != 0 { try readFullInstanceData(for: cls, roPointer: roPtr) }
                      else { print("Warning: Pass 2: Could not get RO pointer for \(cls.name).") }
                 } catch { print("Warning: Pass 2: Error reading instance data for \(cls.name): \(error)") }

                 // Resolve Metaclass and Read Class Data
                 do { try readFullClassData(for: cls) }
                 catch { print("Warning: Pass 2: Error resolving class data for \(cls.name): \(error)") }
             }

            // Resolve Category Target Class Names and Merge
            resolveAndMergeCategories(metadata: &metadata)

            print("ℹ️ ObjCMetadataExtractor: Finished Pass 2.")
         }

        // Pass 2 Helper: Resolves superclass name for a cached class
        private func resolveClassHierarchy(cls: ObjCClass) {
            guard cls.superclassName == nil else { return } // Already resolved or root
            guard let superPtr = cls.getTemporarySuperclassPointer(), superPtr != 0 else {
                 cls.clearTemporarySuperclassPointer(); return // No superclass ptr stored
            }

            if let superCls = classCacheByAddress[superPtr] {
                cls.superclassName = superCls.name
                // print("    [Debug] Pass 2: Resolved superclass for \(cls.name) -> \(superCls.name) (cached)")
            } else {
                do {
                    cls.superclassName = try readClassNameFromClassPtr(superPtr) ?? "<External>"
                    // print("    [Debug] Pass 2: Resolved superclass for \(cls.name) -> \(cls.superclassName!) (direct read)")
                } catch {
                    // print("    [Debug] Pass 2: Failed resolving external superclass 0x\(String(superPtr, radix: 16)) for \(cls.name)")
                    cls.superclassName = "<External>"
                }
            }
            cls.clearTemporarySuperclassPointer()
        }
    
    private func extractClasses(into metadata: inout ExtractedMetadata) throws {
            // Reads class list, resolves RO pointer, calls readClass (updated below)
            guard let classListSection = getSection("__objc_classlist") else { return }
            let sectionFileOffset = UInt64(classListSection.command.offset)
            let sectionSize = classListSection.command.size
            let pointerCount = Int(sectionSize) / POINTER_SIZE

            for i in 0..<pointerCount {
                let pointerOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
                let classVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(pointerOffset))
                guard classVMPtr != 0 else { continue }

                do {
                    // Resolve RO pointer (logic remains similar, might need refinement based on objc version)
                    let roVMPtr = try resolveRODataPtr(fromClassPtr: classVMPtr)
                    guard roVMPtr != 0 else { continue }

                    // Use updated readClass
                    if let cls = try readClassInstanceData(roPointer: roVMPtr, classVMAddress: classVMPtr) {
                        if metadata.classes[cls.name] == nil {
                            metadata.classes[cls.name] = cls
                        } else {
                            // print("Warning: Duplicate class definition found for \(cls.name)")
                        }
                    }
                } catch let error as MachOParseError {
                     print("Warning: Failed to read class data starting at VM address 0x\(String(classVMPtr, radix: 16)): \(error.localizedDescription)")
                }
            }
        }
    
    // IMPLEMENTED: Category Extraction
    private func extractCategories(into metadata: inout ExtractedMetadata) throws {
            guard let catListSection = getSection("__objc_catlist") else { return }
            let sectionFileOffset = UInt64(catListSection.command.offset)
            let sectionSize = catListSection.command.size
            let pointerCount = Int(sectionSize) / POINTER_SIZE

            for i in 0..<pointerCount {
                let pointerOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
                let categoryVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(pointerOffset))
                guard categoryVMPtr != 0 else { continue }

                do {
                    let catFileOffset = try parser.fileOffset(for: categoryVMPtr, parsedData: parsedData)
                    let catData: category_t = try parsedData.dataRegion.read(at: Int(catFileOffset))

                    guard let catName = try readString(atVMAddress: catData.name) else { continue }
                    guard let baseClassName = try readClassNameFromClassPtr(catData.classRef) else { continue }

                    var category = ExtractedCategory(name: catName, className: baseClassName)
                    category.instanceMethods = try readMethodList(atVMAddress: catData.instanceMethods, isClassMethod: false)
                    category.classMethods = try readMethodList(atVMAddress: catData.classMethods, isClassMethod: true)
                    category.protocols = try readProtocolListNames(atVMAddress: catData.protocols)
                    category.instanceProperties = try readPropertyList(atVMAddress: catData.instanceProperties)
                    // ADDED: Read class properties (assuming offset exists in category_t if supported)
                    // The category_t struct might have a 'classProperties' field in newer runtimes.
                    // If not, class properties usually can't be added via categories directly in standard ObjC.
                    // Let's assume for now category_t doesn't contain classProperties pointer.
                    // category.classProperties = try readPropertyList(atVMAddress: catData.classProperties_NEEDS_STRUCT_UPDATE)

                    metadata.categories.append(category)

               } catch let error as MachOParseError {
                   print("Warning: Failed to read category at VM address 0x\(String(categoryVMPtr, radix: 16)): \(error.localizedDescription)")
               }
           }
       }
    
    // --- NEW METHOD: Extract Selector References ---
        private func extractSelectorReferences(into metadata: inout ExtractedMetadata) throws {
            // Find section (allow __DATA or __DATA_CONST)
            guard let selRefsSection = getSection("__objc_selrefs") else {
                print("ℹ️ ObjCMetadataExtractor: No __objc_selrefs section found.")
                return // Nothing to parse
            }

            let sectionFileOffset = UInt64(selRefsSection.command.offset)
            let sectionVMAddr = selRefsSection.command.addr // Base VM address of the section
            let sectionSize = selRefsSection.command.size
            let pointerCount = Int(sectionSize) / POINTER_SIZE

            print("ℹ️ ObjCMetadataExtractor: Parsing __objc_selrefs section (\(pointerCount) potential entries)...")

            for i in 0..<pointerCount {
                // Address *of the pointer* within the selrefs section
                let refPtrFileOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
                let refPtrVMAddress = sectionVMAddr + UInt64(i * POINTER_SIZE)

                // Ensure read is within bounds
                guard refPtrFileOffset + UInt64(POINTER_SIZE) <= parsedData.dataRegion.count else {
                     print("Warning: ObjCMetadataExtractor - Reading selref pointer out of bounds.")
                     break // Stop if out of bounds
                }

                // Read the pointer (VM address) stored at this location
                let targetSelectorNameVMAddr: UInt64 = try parsedData.dataRegion.read(at: Int(refPtrFileOffset))

                // This address points to the actual C string in __objc_methname
                guard targetSelectorNameVMAddr != 0 else {
                    // Null pointer, skip
                    continue
                }

                // Resolve the target pointer to read the selector name string
                do {
                    // Use the existing helper, assuming it handles potential errors
                    if let selectorName = try readString(atVMAddress: targetSelectorNameVMAddr) {
                        // Successfully read name, add the reference
                        metadata.selectorReferences.append(SelectorReference(
                            selectorName: selectorName,
                            referenceAddress: refPtrVMAddress // Store address where ref was found
                        ))
                    } else {
                        // readString returned nil (shouldn't happen if pointer non-zero and resolves)
                        print("Warning: ObjCMetadataExtractor - Failed to read selector name string at resolved address for ref at 0x\(String(refPtrVMAddress, radix: 16))")
                    }
                } catch {
                    // Error resolving pointer or reading string
                     print("Warning: ObjCMetadataExtractor - Failed to resolve/read selector name for ref at 0x\(String(refPtrVMAddress, radix: 16)): \(error)")
                     // Continue to the next reference
                }
            }
             print("ℹ️ ObjCMetadataExtractor: Finished parsing __objc_selrefs.")
        }
    
    // Renamed and updated to handle class props
        private func resolveClassLevelData(for metadata: inout ExtractedMetadata) throws {
            for (_, cls) in metadata.classes {
                do {
                    let isaPtrOffset = try parser.fileOffset(for: cls.vmAddress, parsedData: parsedData)
                    let metaclassPtr: UInt64 = try parsedData.dataRegion.read(at: Int(isaPtrOffset))
                    guard metaclassPtr != 0 else { continue }
                    cls.metaclassVMAddress = metaclassPtr // Store metaclass address

                    let metaROPtr = try resolveRODataPtr(fromClassPtr: metaclassPtr)
                    guard metaROPtr != 0 else { continue }

                    let metaROData: class_ro_t
                    if let cached = metaClassROCache[metaROPtr] {
                        metaROData = cached
                    } else {
                        let metaROFileOffset = try parser.fileOffset(for: metaROPtr, parsedData: parsedData)
                        metaROData = try parsedData.dataRegion.read(at: Int(metaROFileOffset))
                        metaClassROCache[metaROPtr] = metaROData
                    }

                    // Read class methods AND class properties from metaclass's RO data
                    cls.classMethods = try readMethodList(atVMAddress: metaROData.baseMethodList, isClassMethod: true)
                    cls.classProperties = try readPropertyList(atVMAddress: metaROData.baseProperties)

                } catch {
                    print("Warning: Failed to resolve class level data (methods/props) for \(cls.name): \(error)")
                }
            }
        }
    
    // IMPLEMENTED: Merge Categories
    private func mergeCategories(into metadata: inout ExtractedMetadata) {
        print("ℹ️ ObjCMetadataExtractor: Merging categories (Current impl requires base class)...")
            for category in metadata.categories {
                guard let targetClass = metadata.classes[category.className] else { continue }

                // Merge methods (simple append, could add duplicate checking)
                targetClass.instanceMethods.append(contentsOf: category.instanceMethods)
                targetClass.classMethods.append(contentsOf: category.classMethods)
                // Merge instance properties
                targetClass.properties.append(contentsOf: category.instanceProperties)
                // Merge class properties (if read from category struct)
                targetClass.classProperties.append(contentsOf: category.classProperties)

                // Merge protocols
                let existingProtocols = Set(targetClass.adoptedProtocols)
                for protoName in category.protocols {
                    if !existingProtocols.contains(protoName) {
                        targetClass.adoptedProtocols.append(protoName)
                    }
                }
            }
            // metadata.categories.removeAll() // Optional: clear after merge
        }

    /* private func extractClassesAndCategories(into metadata: inout ExtractedMetadata) throws {
        guard let classListSection = getSection("__objc_classlist") else { return }
        let sectionFileOffset = UInt64(classListSection.command.offset)
        let sectionSize = classListSection.command.size
        let pointerCount = Int(sectionSize) / POINTER_SIZE

        for i in 0..<pointerCount {
            let pointerOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
            let classVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(pointerOffset)) // This points to the class *object* itself
            guard classVMPtr != 0 else { continue }

             // --- Read the class structure ---
             // The class object layout is complex (isa, superclass, cache, data).
             // We need the `data` field which points to class_rw_t, which in turn
             // points to class_ro_t (or contains it). This differs across objc versions.
             // Simplification: Assume modern 64-bit where class pointer + 0x20 (offset of 'data' field)
             // gives us a pointer that, after potentially clearing low bits (flags), points to class_rw_t.
             // The class_ro_t pointer is usually the first field within class_rw_t.

             // Let's try a common offset for the 'data' field pointer (adjust if needed based on runtime inspection)
             let dataPtrOffset = 0x20 // Offset of 'bits' or 'data' in struct objc_class
             let dataFieldAddr = classVMPtr + UInt64(dataPtrOffset)
             let dataFieldPtrFileOffset = try parser.fileOffset(for: dataFieldAddr, parsedData: parsedData)
             var classDataPtr: UInt64 = try parsedData.dataRegion.read(at: Int(dataFieldPtrFileOffset))

             // classDataPtr might have flags in lower bits, mask them off if necessary
             // (e.g., RW_REALIZED, RW_FUTURE, etc.). Let's assume we need `& ~3` or similar based on headers.
             // For simplicity here, assume it directly points to class_rw_t or needs minimal cleaning.
             // Let's assume the first field of class_rw_t is the class_ro_t pointer.
             classDataPtr &= ~UInt64(3) // Example mask, adjust based on actual flags

             // Now resolve classDataPtr to read the pointer to class_ro_t
             guard classDataPtr != 0 else { continue } // Skip if data pointer is null
             let roPtrFileOffset = try parser.fileOffset(for: classDataPtr, parsedData: parsedData)
             let roVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(roPtrFileOffset))

            guard roVMPtr != 0 else { continue }

            do {
                if let cls = try readClass(roPointer: roVMPtr, classVMAddress: classVMPtr) {
                    if metadata.classes[cls.name] == nil {
                        metadata.classes[cls.name] = cls
                    }
                }
            } catch let error as MachOParseError {
                 print("Warning: Failed to read class RO data at VM address 0x\(String(roVMPtr, radix: 16)): \(error.localizedDescription)")
            }
        }
        
        // TODO: Extract Categories using __objc_catlist similar to classes
        // Read category_t, find base class, store methods/properties temporarily
        // Needs merging logic later.
    }
*/


    // MARK: - Structure Reading Helpers (Updated)

        /// Reads RO pointer from class/metaclass pointer
        private func resolveRODataPtr(fromClassPtr classPtr: UInt64) throws -> UInt64 {
            print("  [Debug] resolveRODataPtr: Attempting for classPtr 0x\(String(classPtr, radix: 16))")
             guard classPtr != 0 else { return 0 }
             let dataPtrOffset = 0x20
             let dataFieldAddr = classPtr + 0x20
                    let dataFieldPtrFileOffset = try parser.fileOffset(for: dataFieldAddr, parsedData: parsedData)
                    var classDataPtr: UInt64 = try parsedData.dataRegion.read(at: Int(dataFieldPtrFileOffset))
                    print("    [Debug] resolveRODataPtr: Read dataFieldPtr = 0x\(String(classDataPtr, radix: 16)) at file offset \(dataFieldPtrFileOffset)")
                    classDataPtr &= ~UInt64(3) // Mask flags
                    guard classDataPtr != 0 else { print("    [Debug] resolveRODataPtr: dataFieldPtr masked is NULL"); return 0 }

                    let roPtrFileOffset = try parser.fileOffset(for: classDataPtr, parsedData: parsedData)
                    let roVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(roPtrFileOffset))
                    print("    [Debug] resolveRODataPtr: Resolved roVMPtr = 0x\(String(roVMPtr, radix: 16)) at file offset \(roPtrFileOffset)")
                    return roVMPtr
                }
    
    /// Reads instance methods, properties, ivars, adopted protocols from class_ro_t
    private func readClassInstanceData(roPointer: UInt64, classVMAddress: UInt64) throws -> ObjCClass? {
            print("  [Debug] readClassInstanceData: Reading RO at 0x\(String(roPointer, radix: 16)) for class 0x\(String(classVMAddress, radix: 16))")
            let roFileOffset = try parser.fileOffset(for: roPointer, parsedData: parsedData)
            let roData: class_ro_t = try parsedData.dataRegion.read(at: Int(roFileOffset))
            print("    [Debug] readClassInstanceData: Read class_ro_t. Flags: \(roData.flags), NamePtr: 0x\(String(roData.name, radix: 16))")

            guard let name = try readString(atVMAddress: roData.name) else {
                print("    [Debug] readClassInstanceData: FAILED to read class name.")
                return nil
            }
            print("    [Debug] readClassInstanceData: Class Name = \(name)")

           var superclassName: String? = nil
           let superclassPtrAddr = classVMAddress + 0x8
           let superclassPtrFileOffset = try parser.fileOffset(for: superclassPtrAddr, parsedData: parsedData)
           let superclassPtr: UInt64 = try parsedData.dataRegion.read(at: Int(superclassPtrFileOffset))
           if superclassPtr != 0 {
                superclassName = try readClassNameFromClassPtr(superclassPtr)
           }

           let cls = ObjCClass(name: name, vmAddress: classVMAddress, superclassName: superclassName)

            print("      [Debug] Reading instance methods from 0x\(String(roData.baseMethodList, radix: 16))")
                cls.instanceMethods = try readMethodList(atVMAddress: roData.baseMethodList, isClassMethod: false)
                print("      [Debug] Reading properties from 0x\(String(roData.baseProperties, radix: 16))")
                cls.properties = try readPropertyList(atVMAddress: roData.baseProperties)
                print("      [Debug] Reading protocols from 0x\(String(roData.baseProtocols, radix: 16))")
                cls.adoptedProtocols = try readProtocolListNames(atVMAddress: roData.baseProtocols)
                print("      [Debug] Reading ivars from 0x\(String(roData.ivars, radix: 16))")
                cls.ivars = try readIVarList(atVMAddress: roData.ivars)

                print("    [Debug] readClassInstanceData: Finished reading instance data for \(name). Methods: \(cls.instanceMethods.count), Props: \(cls.properties.count), Protos: \(cls.adoptedProtocols.count), IVars: \(cls.ivars.count)")
                return cls
            }
    
    private func readClass(roPointer: UInt64, classVMAddress: UInt64) throws -> ObjCClass? {
        let roFileOffset = try parser.fileOffset(for: roPointer, parsedData: parsedData)
        let roData: class_ro_t = try parsedData.dataRegion.read(at: Int(roFileOffset))

        let name = try readString(atVMAddress: roData.name) ?? "<NoName>"
        let cls = ObjCClass(name: name, vmAddress: classVMAddress)

        // Superclass (Recursive lookup or store address for later resolution)
        // For simplicity, we won't resolve superclass pointer now, just store the name if possible
        // let superclassPtr = // Read from class struct (offset 0x8 usually)
        // if superclassPtr != 0 { cls.superclassName = try readClassNameFromClassPtr(superclassPtr) }

        cls.instanceMethods = try readMethodList(atVMAddress: roData.baseMethodList, isClassMethod: false)

        // Class Methods (need to find metaclass RO data - complex)
        // Simplification: Assume metaclass RO is often located right after class RO, but this is NOT guaranteed.
        // Proper way involves reading metaclass pointer from class struct (offset 0 usually is isa).
        // For now, we skip class methods read this way. They might come from categories.

        cls.properties = try readPropertyList(atVMAddress: roData.baseProperties)

        // Protocols
        cls.adoptedProtocols = try readProtocolListNames(atVMAddress: roData.baseProtocols)

        // IVars (Complex due to offset pointer)
        // cls.ivars = try readIVarList(atVMAddress: roData.ivars)

        return cls
    }

    private func readProtocol(at vmAddress: UInt64) throws -> ObjCProtocol? {
        let fileOffset = try parser.fileOffset(for: vmAddress, parsedData: parsedData)
        let protoData: protocol_t = try parsedData.dataRegion.read(at: Int(fileOffset))

        guard let name = try readString(atVMAddress: protoData.name) else { return nil }
        let proto = ObjCProtocol(name: name)

        proto.baseProtocols = try readProtocolListNames(atVMAddress: protoData.protocols)
        proto.instanceMethods = try readMethodList(atVMAddress: protoData.instanceMethods, isClassMethod: false)
        proto.classMethods = try readMethodList(atVMAddress: protoData.classMethods, isClassMethod: true)
        proto.optionalInstanceMethods = try readMethodList(atVMAddress: protoData.optionalInstanceMethods, isClassMethod: false)
        proto.optionalClassMethods = try readMethodList(atVMAddress: protoData.optionalClassMethods, isClassMethod: true)
        proto.instanceProperties = try readPropertyList(atVMAddress: protoData.instanceProperties)
        // ADDED: Read class properties pointer from protocol_t if it exists
        // Need to check protocol_t structure for a classProperties field in target runtime.
        // Assuming it might exist at some offset (e.g., after instanceProperties)
        // let classPropertiesPtr = // Read pointer from appropriate offset in protoData
        // proto.classProperties = try readPropertyList(atVMAddress: classPropertiesPtr)

        return proto
    }

       private func readFullInstanceData(for cls: ObjCClass, roPointer: UInt64) throws {
           let roFileOffset = try parser.fileOffset(for: roPointer, parsedData: parsedData)
           guard roFileOffset + UInt64(MemoryLayout<class_ro_t>.stride) <= parsedData.dataRegion.count else { return }
           let roData: class_ro_t = try parsedData.dataRegion.read(at: Int(roFileOffset))

           cls.instanceMethods = try readMethodList(atVMAddress: roData.baseMethodList, isClassMethod: false)
           cls.properties = try readPropertyList(atVMAddress: roData.baseProperties)
           cls.adoptedProtocols = try readProtocolListNames(atVMAddress: roData.baseProtocols)
           cls.ivars = try readIVarList(atVMAddress: roData.ivars)
            // print("    [Debug] Pass 2: Read instance data for \(cls.name). Methods: \(cls.instanceMethods.count), Props: \(cls.properties.count), Protos: \(cls.adoptedProtocols.count), IVars: \(cls.ivars.count)")
       }
    
        private func readFullClassData(for cls: ObjCClass) throws {
            guard cls.metaclassVMAddress == nil else { return }

            let isaPtrOffset = try parser.fileOffset(for: cls.vmAddress, parsedData: parsedData)
            guard isaPtrOffset + UInt64(POINTER_SIZE) <= parsedData.dataRegion.count else { return }
            let metaclassPtr: UInt64 = try parsedData.dataRegion.read(at: Int(isaPtrOffset))
            guard metaclassPtr != 0 else { return }
            cls.metaclassVMAddress = metaclassPtr

            let metaROPtr = try resolveRODataPtr(fromClassPtr: metaclassPtr)
            guard metaROPtr != 0 else { return }

            let metaROData: class_ro_t
            if let cached = metaClassROCache[metaROPtr] { metaROData = cached }
            else { let metaROFileOffset = try parser.fileOffset(for: metaROPtr, parsedData: parsedData); guard metaROFileOffset + UInt64(MemoryLayout<class_ro_t>.stride) <= parsedData.dataRegion.count else { return }; metaROData = try parsedData.dataRegion.read(at: Int(metaROFileOffset)); metaClassROCache[metaROPtr] = metaROData }

            cls.classMethods = try readMethodList(atVMAddress: metaROData.baseMethodList, isClassMethod: true)
            cls.classProperties = try readPropertyList(atVMAddress: metaROData.baseProperties)
            // print("    [Debug] Pass 2: Read class data for \(cls.name). Methods: \(cls.classMethods.count), Props: \(cls.classProperties.count)")
        }

        private func resolveAndMergeCategories(metadata: inout ExtractedMetadata) {
            print("ℹ️ ObjCMetadataExtractor: Pass 2: Resolving and merging categories...")
            var unmergedCategories: [ExtractedCategory] = []

            for var category in metadata.categories {
                guard let targetPtr = category.getTemporaryTargetClassPointer() else { continue }

                if let targetCls = classCacheByAddress[targetPtr] {
                    category.className = targetCls.name
                    print("    [Debug] Merging category \(category.name) into \(targetCls.name)")
                    targetCls.instanceMethods.append(contentsOf: category.instanceMethods)
                    targetCls.classMethods.append(contentsOf: category.classMethods)
                    targetCls.properties.append(contentsOf: category.instanceProperties)
                    targetCls.classProperties.append(contentsOf: category.classProperties)
                    let existingProtocols = Set(targetCls.adoptedProtocols)
                    for protoName in category.protocols { if !existingProtocols.contains(protoName) { targetCls.adoptedProtocols.append(protoName) } }
                } else {
                    do {
                        category.className = try readClassNameFromClassPtr(targetPtr) ?? "<External>"
                        print("    [Debug] Category \(category.name) targets external/uncached class \(category.className)")
                        unmergedCategories.append(category)
                    } catch {
                         print("    [Debug] Failed resolving external category target 0x\(String(targetPtr, radix: 16)) for category \(category.name)")
                         category.className = "<Unknown External>"
                         unmergedCategories.append(category)
                    }
                }
                category.clearTemporaryTargetClassPointer()
            }
            metadata.categories = unmergedCategories
        }
    
    private func readMethodList(atVMAddress listVMPtr: UInt64, isClassMethod: Bool) throws -> [ObjCMethod] {
             guard listVMPtr != 0 else { return [] }
             print("      [Debug] readMethodList: Reading list at 0x\(String(listVMPtr, radix: 16))")

        let listFileOffset = try parser.fileOffset(for: listVMPtr, parsedData: parsedData)
                 let header: objc_list_header_t = try parsedData.dataRegion.read(at: Int(listFileOffset))
                 let count = Int(header.countValue)
                 let elementSize = Int(header.elementSize)
                 print("        [Debug] readMethodList: Count=\(count), EntSize=\(elementSize)")
                 guard elementSize >= MemoryLayout<method_t>.stride else {
                      print("        [Debug] readMethodList: ERROR - entsize (\(elementSize)) smaller than method_t stride (\(MemoryLayout<method_t>.stride)). Aborting list read.")
                      return []
                 }
        var methods: [ObjCMethod] = []
                 var currentMethodFileOffset = listFileOffset + UInt64(MemoryLayout<objc_list_header_t>.size)

                 for i in 0..<count {
                     print("        [Debug] readMethodList: Reading method #\(i+1) at file offset \(currentMethodFileOffset)")
                     guard currentMethodFileOffset + UInt64(elementSize) <= parsedData.dataRegion.count else {
                         print("        [Debug] readMethodList: ERROR - Read out of bounds for method #\(i+1). Aborting list read.")
                         break
                     }
                     let methodData: method_t = try parsedData.dataRegion.read(at: Int(currentMethodFileOffset))

                     let name = try readString(atVMAddress: methodData.name) ?? "?SEL? (\(methodData.name))"
                     let types = try readString(atVMAddress: methodData.types) ?? "? (\(methodData.types))"
                     print("          [Debug] readMethodList: Name='\(name)', Types='\(types)', Imp=0x\(String(methodData.imp, radix: 16))")

                     methods.append(ObjCMethod(name: name, typeEncoding: types, implementationAddress: methodData.imp, isClassMethod: isClassMethod))
                     currentMethodFileOffset += UInt64(elementSize)
                 }
                 print("      [Debug] readMethodList: Finished list at 0x\(String(listVMPtr, radix: 16)). Found \(methods.count) methods.")
                 return methods
             }

    private func readPropertyList(atVMAddress listVMPtr: UInt64) throws -> [ObjCProperty] {
        guard listVMPtr != 0 else { return [] }

        let listFileOffset = try parser.fileOffset(for: listVMPtr, parsedData: parsedData)
        let header: objc_list_header_t = try parsedData.dataRegion.read(at: Int(listFileOffset))
        let count = Int(header.countValue)
        let elementSize = MemoryLayout<property_t>.size
        var properties: [ObjCProperty] = []
        properties.reserveCapacity(count)

        var currentPropertyOffset = listFileOffset + UInt64(MemoryLayout<objc_list_header_t>.size)

        for _ in 0..<count {
            let propData: property_t = try parsedData.dataRegion.read(at: Int(currentPropertyOffset))
            let name = try readString(atVMAddress: propData.name) ?? "?PROP?"
            let attrs = try readString(atVMAddress: propData.attributes) ?? ""

            properties.append(ObjCProperty(name: name, attributes: attrs))
            currentPropertyOffset += UInt64(elementSize)
        }
        return properties
    }

    private func readProtocolListNames(atVMAddress listVMPtr: UInt64) throws -> [String] {
            guard listVMPtr != 0 else { return [] }

            let listFileOffset = try parser.fileOffset(for: listVMPtr, parsedData: parsedData)
            let count: UInt64 = try parsedData.dataRegion.read(at: Int(listFileOffset))
            guard count < 500 else {
                print("Warning: Unusually large protocol list count (\(count)) at 0x\(String(listVMPtr, radix: 16)), skipping.")
                return []
            }

            var names: [String] = []
            names.reserveCapacity(Int(count))
            var currentPtrOffset = listFileOffset + UInt64(POINTER_SIZE)

            for _ in 0..<Int(count) {
                 guard currentPtrOffset + UInt64(POINTER_SIZE) <= parsedData.dataRegion.count else {
                     print("Warning: Protocol list pointer read out of bounds at offset \(currentPtrOffset)")
                     break
                 }

                let protocolVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(currentPtrOffset))
                if protocolVMPtr == 0 { continue }

                do {
                    let namePtrAddr = protocolVMPtr + 0x8
                    let namePtrFileOffset = try parser.fileOffset(for: namePtrAddr, parsedData: parsedData)
                    let namePtr: UInt64 = try parsedData.dataRegion.read(at: Int(namePtrFileOffset))

                    if let name = try readString(atVMAddress: namePtr) {
                        names.append(name)
                    } else {
                         print("Warning: Failed to read protocol name string pointed to by 0x\(String(namePtr, radix: 16))")
                    }
                } catch {
                     print("Warning: Failed to read protocol name from list at ptr 0x\(String(protocolVMPtr, radix: 16)): \(error)")
                }
                currentPtrOffset += UInt64(POINTER_SIZE)
            }
            return names
        }
    
        private func readIVarList(atVMAddress listVMPtr: UInt64) throws -> [ObjCIVar] {
            guard listVMPtr != 0 else { return [] }

            let listFileOffset = try parser.fileOffset(for: listVMPtr, parsedData: parsedData)
            let header: objc_list_header_t = try parsedData.dataRegion.read(at: Int(listFileOffset))
            let count = Int(header.countValue)
            let elementSize = Int(header.elementSize)
            guard elementSize >= MemoryLayout<ivar_t>.size else {
                 print("Warning: Ivar list entsize (\(elementSize)) smaller than expected (\(MemoryLayout<ivar_t>.size)), skipping.")
                 return []
            }

            var ivars: [ObjCIVar] = []
            ivars.reserveCapacity(count)

            var currentIvarOffset = listFileOffset + UInt64(MemoryLayout<objc_list_header_t>.size)

            for _ in 0..<count {
                let ivarData: ivar_t = try parsedData.dataRegion.read(at: Int(currentIvarOffset))

                let name = try readString(atVMAddress: ivarData.name) ?? "?IVAR?"
                let typeEnc = try readString(atVMAddress: ivarData.type) ?? "?"

                var actualOffset: UInt64 = 0
                if ivarData.offset_ptr != 0 {
                     do {
                         let offsetValueFileOffset = try parser.fileOffset(for: ivarData.offset_ptr, parsedData: parsedData)
                         actualOffset = try parsedData.dataRegion.read(at: Int(offsetValueFileOffset))
                     } catch {
                         print("Warning: Failed to resolve ivar offset pointer 0x\(String(ivarData.offset_ptr, radix: 16)) for ivar \(name): \(error)")
                     }
                } else {
                     print("Warning: Ivar offset pointer is NULL for ivar \(name)")
                }

                 let alignment = 1 << ivarData.alignment_raw

                ivars.append(ObjCIVar(
                    name: name,
                    typeEncoding: typeEnc,
                    offset: actualOffset,
                    size: ivarData.size,
                    alignment: Int(alignment)
                ))
                currentIvarOffset += UInt64(elementSize)
            }
            return ivars
        }

    private func readString(atVMAddress vmAddress: UInt64) throws -> String? {
            guard vmAddress != 0 else { return nil }
            print("        [Debug] readString: Attempting resolve for VMAddr 0x\(String(vmAddress, radix: 16))")
            let fileOffset = try parser.fileOffset(for: vmAddress, parsedData: parsedData)
            print("          [Debug] readString: Resolved to FileOffset \(fileOffset)")
            guard fileOffset < parsedData.dataRegion.count else {
                 print("          [Debug] readString: ERROR - Resolved file offset \(fileOffset) is out of bounds (\(parsedData.dataRegion.count)).")
                 throw MachOParseError.stringReadOutOfBounds(offset: fileOffset)
            }
            do {
               let str = try parsedData.dataRegion.readCString(at: Int(fileOffset))
               print("          [Debug] readString: Success = '\(str.prefix(50))'")
               return str
            } catch {
                 print("          [Debug] readString: ERROR - readCString failed at offset \(fileOffset): \(error)")
                 throw error
            }
        }

    private func readClassNameFromClassPtr(_ classPtr: UInt64) throws -> String? {
        guard classPtr != 0 else { return nil }
        let roPtr = try resolveRODataPtr(fromClassPtr: classPtr)
        guard roPtr != 0 else { return nil }
        let roFileOffset = try parser.fileOffset(for: roPtr, parsedData: parsedData)
        let namePtrAddr = roPtr + 0x10
        let namePtrFileOffset = try parser.fileOffset(for: namePtrAddr, parsedData: parsedData)
        let namePtr: UInt64 = try parsedData.dataRegion.read(at: Int(namePtrFileOffset))
        return try readString(atVMAddress: namePtr)
    }
}

fileprivate extension ObjCMethod { init(n:String,t:String,i:UInt64,i classMeth:Bool){self.init(name:n,typeEncoding:t,implementationAddress:i,isClassMethod:classMeth)} }
fileprivate extension ObjCProperty { init(n:String,a:String){self.init(name:n,attributes:a)} }
fileprivate extension ObjCIVar { init(n:String,t:String,o:UInt64,s:UInt32,a:Int){self.init(name:n,typeEncoding:t,offset:o,size:s,alignment:a)} }
fileprivate extension MachOParser { func fileOffset(for vm: UInt64, p: ParsedMachOData) throws -> UInt64 { try self.fileOffset(for:vm, parsedData:p)} }
fileprivate extension ObjCMetadataExtractor { func readString(at vm: UInt64) throws -> String? { try self.readString(atVMAddress: vm) } }
fileprivate extension ObjCMetadataExtractor { func readMethodList(at vm: UInt64, i: Bool) throws -> [ObjCMethod] { try self.readMethodList(atVMAddress: vm, isClassMethod: i) } }
fileprivate extension ObjCMetadataExtractor { func readPropertyList(at vm: UInt64) throws -> [ObjCProperty] { try self.readPropertyList(atVMAddress: vm) } }
fileprivate extension ObjCMetadataExtractor { func readProtocolListNames(at vm: UInt64) throws -> [String] { try self.readProtocolListNames(atVMAddress: vm) } }
fileprivate extension ObjCMetadataExtractor { func readIVarList(at vm: UInt64) throws -> [ObjCIVar] { try self.readIVarList(atVMAddress: vm) } }
fileprivate extension HeaderGenerator { convenience init(m: ExtractedMetadata) { self.init(metadata: m)} }
fileprivate extension HeaderGenerator { func generateHeader(i: Bool) async throws -> String { try await self.generateHeader(includeIvarsInHeader: i)} }
fileprivate extension SwiftMetadataExtractor { convenience init(p: ParsedMachOData, p parser: MachOParser, d: DynamicSymbolLookup.SwiftDemangleFunc?) { self.init(parsedData:p, parser:parser, demanglerFunc: d)} }
