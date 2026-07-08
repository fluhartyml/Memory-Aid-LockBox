//
//  ShareSheetView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//
//  Every record type is shareable (roadmap: universal sharing). The system
//  share sheet gets a full text summary that includes the record's OWN fields —
//  a receipt shares its line items + totals + payment, a contact its phone/
//  email/address, a card its number/expiry, an appointment its date/provider,
//  an account its login — not just the generic title/notes. Images ride along
//  as separate share items so AirDrop/Messages/Mail all carry the picture too.
//

#if os(iOS)
import SwiftUI
import UIKit

struct ShareSheetView: UIViewControllerRepresentable {
    let item: VaultItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var shareItems: [Any] = [RecordShare.summary(for: item)]
        for data in item.imageData {
            if let image = UIImage(data: data) { shareItems.append(image) }
        }
        return UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
