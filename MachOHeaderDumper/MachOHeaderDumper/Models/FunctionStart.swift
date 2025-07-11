//
//  FunctionStart.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Models/FunctionStart.swift (or ParsedMachOData.swift)

import Foundation

struct FunctionStart: Identifiable, Hashable {
    let id = UUID()
    let address: UInt64 // The absolute VM address of the function start
}

// No extra Equatable needed if only using address for comparison (default struct Equatable works if needed)
