//
//  ShareSheetView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

#if os(iOS)
import SwiftUI
import UIKit

struct ShareSheetView: UIViewControllerRepresentable {
    let item: VaultItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var shareItems: [Any] = []

        // Build a text summary
        var text = item.title
        if !item.pin.isEmpty {
            text += "\nCode: \(item.pin)"
        }
        if !item.notes.isEmpty {
            text += "\n\(item.notes)"
        }
        shareItems.append(text)

        // Attach images
        for data in item.imageData {
            if let image = UIImage(data: data) {
                shareItems.append(image)
            }
        }

        return UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
