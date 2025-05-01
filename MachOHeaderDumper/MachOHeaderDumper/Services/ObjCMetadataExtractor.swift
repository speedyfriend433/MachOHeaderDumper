//
//  ObjCMetadataExtractor.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import Foundation

class ObjCMetadataExtractor {
    private let parsedData: ParsedMachOData
    private let parser: MachOParser
    private var sectionCache: [String: ParsedSection] = [:]
    private var metaClassROCache: [UInt64: class_ro_t] = [:] // Cache metaclass RO data


    init(parsedData: ParsedMachOData, parser: MachOParser) {
        self.parsedData = parsedData
        self.parser = parser
    }

    /// Main function to extract all Objective-C metadata.
    func extract() async throws -> ExtractedMetadata {
            var metadata = ExtractedMetadata()
            metaClassROCache.removeAll()

            try cacheRequiredSections()
            try extractProtocols(into: &metadata)
            try extractClasses(into: &metadata) // Reads instance data
            try extractCategories(into: &metadata)
            try resolveClassLevelData(for: &metadata) // Renamed from resolveClassMethods
            mergeCategories(into: &metadata)

            print("Extraction: Found \(metadata.classes.count) classes, \(metadata.protocols.count) protocols, \(metadata.categories.count) categories.")
            return metadata
        }

    // MARK: - Section Caching

    private func cacheRequiredSections() throws {
        let required = [
            ("__DATA_CONST", "__objc_classlist"), ("__DATA", "__objc_classlist"), // Allow either segment
            ("__DATA_CONST", "__objc_protolist"), ("__DATA", "__objc_protolist"),
            ("__DATA_CONST", "__objc_catlist"), ("__DATA", "__objc_catlist"),
            ("__TEXT", "__objc_classname"),
            ("__TEXT", "__objc_methname"),
            ("__TEXT", "__objc_methtype"),
            ("__DATA_CONST", "__objc_const"), // Needed for class_ro_t
             // Add others if needed: __objc_selrefs, __objc_superrefs, __objc_ivar, etc.
        ]
        for (seg, sect) in required {
                 if let section = parsedData.section(segmentName: seg, sectionName: sect) {
                     sectionCache["\(seg)/\(sect)"] = section
                     if sectionCache[sect] == nil { sectionCache[sect] = section }
                 }
             }
        // --- MODIFIED ERROR CHECK ---
            // Check if *any* core ObjC sections were found. If not, it's likely not an ObjC binary.
            let hasClassList = sectionCache["__objc_classlist"] != nil
            let hasProtoList = sectionCache["__objc_protolist"] != nil
            let hasSelRefs = sectionCache["__objc_selrefs"] != nil // Add check for selrefs maybe?
            let hasConst = sectionCache["__objc_const"] != nil   // Const section is crucial

            // If none of the primary ObjC data sections are present, throw a specific error.
            guard hasClassList || hasProtoList || hasSelRefs || hasConst else {
                 throw MachOParseError.noObjectiveCMetadataFound // Define this new error case
            }

            // Keep checks for absolutely essential sections for subsequent steps if needed
            // For example, if class list exists, we probably need __objc_const too.
            // Guard sectionCache["__objc_classname"] != nil else { throw MachOParseError.sectionNotFound(segment: "__TEXT", section: "__objc_classname") }
            // Guard sectionCache["__objc_methname"] != nil else { throw MachOParseError.sectionNotFound(segment: "__TEXT", section: "__objc_methname") }
            // Guard sectionCache["__objc_methtype"] != nil else { throw MachOParseError.sectionNotFound(segment: "__TEXT", section: "__objc_methtype") }

             // If class list is present, __objc_const is needed to read class_ro_t
             if hasClassList && !hasConst {
                 throw MachOParseError.sectionNotFound(segment: "__DATA_CONST", section: "__objc_const")
             }
        }

    private func getSection(_ name: String) -> ParsedSection? {
        return sectionCache[name]
    }

    // MARK: - Extraction Logic

        private func extractProtocols(into metadata: inout ExtractedMetadata) throws {
            // Logic remains mostly the same, relies on readProtocol which is updated below
            guard let protoListSection = getSection("__objc_protolist") else { return }
            let sectionFileOffset = UInt64(protoListSection.command.offset)
            let sectionSize = protoListSection.command.size
            let pointerCount = Int(sectionSize) / POINTER_SIZE

            for i in 0..<pointerCount {
                let pointerOffset = sectionFileOffset + UInt64(i * POINTER_SIZE)
                let protocolVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(pointerOffset))
                guard protocolVMPtr != 0 else { continue }

                do {
                    // Use updated readProtocol
                    if let proto = try readProtocol(at: protocolVMPtr) {
                        if metadata.protocols[proto.name] == nil {
                            metadata.protocols[proto.name] = proto
                        } else {
                            // Handle potential duplicate protocol definitions? Maybe merge later.
                            // print("Warning: Duplicate protocol definition found for \(proto.name)")
                        }
                    }
                } catch let error as MachOParseError {
                    print("Warning: Failed to read protocol at VM address 0x\(String(protocolVMPtr, radix: 16)): \(error.localizedDescription)")
                }
            }
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
                    cls.classProperties = try readPropertyList(atVMAddress: metaROData.baseProperties) // <-- ADDED

                } catch {
                    print("Warning: Failed to resolve class level data (methods/props) for \(cls.name): \(error)")
                }
            }
        }
    
    // IMPLEMENTED: Merge Categories
    private func mergeCategories(into metadata: inout ExtractedMetadata) {
            for category in metadata.categories {
                guard let targetClass = metadata.classes[category.className] else { continue }

                // Merge methods (simple append, could add duplicate checking)
                targetClass.instanceMethods.append(contentsOf: category.instanceMethods)
                targetClass.classMethods.append(contentsOf: category.classMethods)
                // Merge instance properties
                targetClass.properties.append(contentsOf: category.instanceProperties)
                // Merge class properties (if read from category struct)
                targetClass.classProperties.append(contentsOf: category.classProperties) // <-- ADDED

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
             guard classPtr != 0 else { return 0 }
             // Offset of 'bits' or 'data' field in struct objc_class (typically 0x20)
             let dataPtrOffset = 0x20
             let dataFieldAddr = classPtr + UInt64(dataPtrOffset)
             let dataFieldPtrFileOffset = try parser.fileOffset(for: dataFieldAddr, parsedData: parsedData)
             var classDataPtr: UInt64 = try parsedData.dataRegion.read(at: Int(dataFieldPtrFileOffset))

             // Mask pointer bits if necessary (common mask is ~3 for alignment/flags)
             classDataPtr &= ~UInt64(3)
             guard classDataPtr != 0 else { return 0 }

             // Read the pointer to class_ro_t (usually first field in class_rw_t)
             let roPtrFileOffset = try parser.fileOffset(for: classDataPtr, parsedData: parsedData)
             let roVMPtr: UInt64 = try parsedData.dataRegion.read(at: Int(roPtrFileOffset))
             return roVMPtr
        }
    
    /// Reads instance methods, properties, ivars, adopted protocols from class_ro_t
       private func readClassInstanceData(roPointer: UInt64, classVMAddress: UInt64) throws -> ObjCClass? {
           let roFileOffset = try parser.fileOffset(for: roPointer, parsedData: parsedData)
           let roData: class_ro_t = try parsedData.dataRegion.read(at: Int(roFileOffset))

           let name = try readString(atVMAddress: roData.name) ?? "<NoName>"

           // Resolve superclass name immediately if possible
           var superclassName: String? = nil
           // Need to read superclass pointer from the class struct itself (offset 0x8 usually)
           let superclassPtrAddr = classVMAddress + 0x8
           let superclassPtrFileOffset = try parser.fileOffset(for: superclassPtrAddr, parsedData: parsedData)
           let superclassPtr: UInt64 = try parsedData.dataRegion.read(at: Int(superclassPtrFileOffset))
           if superclassPtr != 0 {
                superclassName = try readClassNameFromClassPtr(superclassPtr)
           }

           let cls = ObjCClass(name: name, vmAddress: classVMAddress, superclassName: superclassName)

           // Instance Methods from RO
           cls.instanceMethods = try readMethodList(atVMAddress: roData.baseMethodList, isClassMethod: false)

           // Properties from RO
           cls.properties = try readPropertyList(atVMAddress: roData.baseProperties)

           // Protocols from RO
           cls.adoptedProtocols = try readProtocolListNames(atVMAddress: roData.baseProtocols)

           // IMPLEMENTED: IVars from RO
           cls.ivars = try readIVarList(atVMAddress: roData.ivars)

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


        // Instance Methods
        cls.instanceMethods = try readMethodList(atVMAddress: roData.baseMethodList, isClassMethod: false)

        // Class Methods (need to find metaclass RO data - complex)
        // Simplification: Assume metaclass RO is often located right after class RO, but this is NOT guaranteed.
        // Proper way involves reading metaclass pointer from class struct (offset 0 usually is isa).
        // For now, we skip class methods read this way. They might come from categories.

        // Properties
        cls.properties = try readPropertyList(atVMAddress: roData.baseProperties)

        // Protocols
        cls.adoptedProtocols = try readProtocolListNames(atVMAddress: roData.baseProtocols)

        // IVars (Complex due to offset pointer)
        // cls.ivars = try readIVarList(atVMAddress: roData.ivars)

        return cls
    }

    // Update readProtocol to include class properties
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

    // Generic list reader for methods
    private func readMethodList(atVMAddress listVMPtr: UInt64, isClassMethod: Bool) throws -> [ObjCMethod] {
        guard listVMPtr != 0 else { return [] }

        let listFileOffset = try parser.fileOffset(for: listVMPtr, parsedData: parsedData)
        let header: objc_list_header_t = try parsedData.dataRegion.read(at: Int(listFileOffset))
        let count = Int(header.countValue)
        // Ensure entsize matches expected method_t size. Could use elementSize instead if available/reliable.
        let elementSize = MemoryLayout<method_t>.size
        var methods: [ObjCMethod] = []
        methods.reserveCapacity(count)

        var currentMethodOffset = listFileOffset + UInt64(MemoryLayout<objc_list_header_t>.size)

        for _ in 0..<count {
            let methodData: method_t = try parsedData.dataRegion.read(at: Int(currentMethodOffset))

            // Resolve selector name and type encoding strings
            let name = try readString(atVMAddress: methodData.name) ?? "?SEL?"
            let types = try readString(atVMAddress: methodData.types) ?? "?"

            methods.append(ObjCMethod(
                name: name,
                typeEncoding: types,
                implementationAddress: methodData.imp, // Store the IMP VM address
                isClassMethod: isClassMethod
            ))
            currentMethodOffset += UInt64(elementSize)
        }
        return methods
    }

    // Generic list reader for properties
    private func readPropertyList(atVMAddress listVMPtr: UInt64) throws -> [ObjCProperty] {
        guard listVMPtr != 0 else { return [] }

        let listFileOffset = try parser.fileOffset(for: listVMPtr, parsedData: parsedData)
        let header: objc_list_header_t = try parsedData.dataRegion.read(at: Int(listFileOffset))
        let count = Int(header.countValue)
        let elementSize = MemoryLayout<property_t>.size // Assume direct list of property_t
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

    // IMPLEMENTED: Safer protocol list reading (assuming count-prefixed list)
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
                    // FIX: Remove unused protoFileOffset calculation
                    // let protoFileOffset = try parser.fileOffset(for: protocolVMPtr, parsedData: parsedData)

                    // Read only the name field offset from protocol_t
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
    
    // IMPLEMENTED: IVAR List reading with offset resolution
        private func readIVarList(atVMAddress listVMPtr: UInt64) throws -> [ObjCIVar] {
            guard listVMPtr != 0 else { return [] }

            let listFileOffset = try parser.fileOffset(for: listVMPtr, parsedData: parsedData)
            let header: objc_list_header_t = try parsedData.dataRegion.read(at: Int(listFileOffset))
            let count = Int(header.countValue)
            // Use entsize from header, should match ivar_t size
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

                // Resolve the pointer to the offset value
                var actualOffset: UInt64 = 0 // Default to 0 if resolution fails
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

    // Helper to read CString given a VM address pointer
    private func readString(atVMAddress vmAddress: UInt64) throws -> String? {
        guard vmAddress != 0 else { return nil }
        let fileOffset = try parser.fileOffset(for: vmAddress, parsedData: parsedData)
        // Make sure offset is within the bounds of the data region
        guard fileOffset < parsedData.dataRegion.count else {
             throw MachOParseError.stringReadOutOfBounds(offset: fileOffset)
        }
        return try parsedData.dataRegion.readCString(at: Int(fileOffset))
    }

// Helper to read class name directly from class pointer
    private func readClassNameFromClassPtr(_ classPtr: UInt64) throws -> String? {
        guard classPtr != 0 else { return nil }
        let roPtr = try resolveRODataPtr(fromClassPtr: classPtr)
        guard roPtr != 0 else { return nil }
        let roFileOffset = try parser.fileOffset(for: roPtr, parsedData: parsedData)
        // Read only the name field offset from class_ro_t (offset 0x10 usually)
        let namePtrAddr = roPtr + 0x10 // Offset of 'name' field
        let namePtrFileOffset = try parser.fileOffset(for: namePtrAddr, parsedData: parsedData)
        let namePtr: UInt64 = try parsedData.dataRegion.read(at: Int(namePtrFileOffset))
        return try readString(atVMAddress: namePtr)
    }
}
