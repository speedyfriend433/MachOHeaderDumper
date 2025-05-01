//
//  StatusErrorView.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 5/1/25.
//

// File: Views/SupportingViews/StatusErrorView.swift (Display Demangler Status)

import SwiftUI

struct StatusErrorView: View {
    let isLoading: Bool
    let statusMessage: String
    let errorMessage: String?
    let parsedDataIsAvailable: Bool
    // ADDED: Demangler status
    var demanglerStatus: DemanglerStatus = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { // Align leading for both lines
            HStack {
                if isLoading { ProgressView().scaleEffect(0.7) }
                Text(statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                // ADDED: Display Demangler Status (only if not idle)
                if demanglerStatus != .idle {
                    Text(demanglerStatus.description)
                         .font(.caption2) // Make it smaller
                         .padding(.horizontal, 4)
                         .padding(.vertical, 1)
                         .background(demanglerStatus.color.opacity(0.2)) // Use status color
                         .foregroundColor(demanglerStatus.color)
                         .cornerRadius(4)
                }
            }

            // Error message display remains the same
            if let errorMsg = errorMessage {
                let isNoObjCMetaError = errorMsg.contains("No Objective-C")
                let errorColor: Color = (isNoObjCMetaError && parsedDataIsAvailable) ? .orange : .red
                Text(errorMsg)
                    .font(.caption)
                    .foregroundColor(errorColor)
                    .frame(maxWidth: .infinity, alignment: .leading) // Keep alignment
            }
        }
        .padding(.horizontal)
    }
}
