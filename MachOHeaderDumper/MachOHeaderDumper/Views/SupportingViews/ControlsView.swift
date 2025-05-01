//
//  ControlsView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/SupportingViews/ControlsView.swift

import SwiftUI

// MARK: - Extracted View Structs (Definitions needed in separate files or below)

struct ControlsView: View {
    let isLoading: Bool
    let importAction: () -> Void
    var body: some View { Button(action: importAction) { Label("Import File...", systemImage: "doc.badge.plus") }.buttonStyle(.borderedProminent).padding(.horizontal).disabled(isLoading) }
}
