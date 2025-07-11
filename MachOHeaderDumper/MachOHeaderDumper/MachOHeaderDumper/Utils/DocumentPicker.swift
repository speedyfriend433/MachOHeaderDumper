//
//  DocumentPicker.swift
//  MachOHeaderDumper
//
//  Created by 이지안 on 4/30/25.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

internal struct DocumentPicker: UIViewControllerRepresentable {
    private var allowedContentTypes: [UTType] = [ .item ]
    var onDocumentPicked: (URL) -> Void

    internal init(onDocumentPicked: @escaping (URL) -> Void) {
        self.onDocumentPicked = onDocumentPicked
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    internal class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ documentPicker: DocumentPicker) {
            self.parent = documentPicker
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                print("Document Picker returned no URL.")
                return
            }
            parent.onDocumentPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("Document Picker was cancelled.")
        }
    }
}
