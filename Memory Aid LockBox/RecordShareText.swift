//
//  RecordShareText.swift
//  Memory Aid LockBox
//
//  Cross-platform text summary of a record for sharing. iOS shares this plus the
//  images (UIActivityViewController); macOS shares this text via ShareLink. Kept
//  here (not inside the iOS-only ShareSheetView) so both platforms use one source
//  of truth for what a shared record says.
//

import Foundation

enum RecordShare {
    /// A complete, human-readable summary of the record, including whichever
    /// template fields it carries. Empty fields are skipped so it stays clean
    /// regardless of type.
    static func summary(for item: VaultItem) -> String {
        var text = item.title.isEmpty ? "Untitled" : item.title
        func line(_ label: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { text += "\n\(label): \(v)" }
        }

        // Receipt
        if item.isReceipt || item.folder?.template == .receipts {
            line("Address", item.receiptAddress)
            line("Phone", item.receiptPhone)
            text += "\nDate: \(item.receiptDate.formatted(date: .abbreviated, time: .shortened))"
            let items = item.receiptItems.filter { !$0.name.isEmpty || !$0.price.isEmpty }
            if !items.isEmpty {
                text += "\n\nItems:"
                for li in items {
                    text += "\n  \(li.name)\(li.price.isEmpty ? "" : "  \(li.price)")"
                }
            }
            line("Subtotal", item.receiptSubtotal)
            line("Tax", item.receiptTax)
            line("Total", item.receiptTotal)
            if !item.receiptPaymentType.isEmpty || !item.receiptCardLast4.isEmpty {
                let last4 = item.receiptCardLast4.isEmpty ? "" : " ••\(item.receiptCardLast4)"
                text += "\nPaid: \(item.receiptPaymentType)\(last4)"
            }
        }

        // Contact
        if item.isContact || item.folder?.template == .contacts {
            line("Phone", item.contactPhone)
            line("Email", item.contactEmail)
            line("Address", item.contactAddress)
            if item.isBusinessContact {
                line("Website", item.contactWebsite)
                line("Hours", item.contactHours)
            } else {
                line("Source", item.contactRelationship)
            }
        }

        // Appointment
        if item.isAppointment || item.folder?.template == .appointments {
            line("Provider", item.apptProvider)
            text += "\nWhen: \(item.apptDate.formatted(date: .abbreviated, time: .shortened))"
            line("Prep", item.apptPrep)
            line("Address", item.apptAddress)
            line("Phone", item.apptPhone)
        }

        // Account / codes
        if item.isCodesAccount || item.folder?.template == .codesAccounts {
            line("Username / email", item.codeUsername)
            line("Password", item.codePassword)
            line("Website", item.codeWebsite)
        }

        // Card
        if item.isCard || item.folder?.template == .cards {
            line("Type", CardType(rawValue: item.cardTypeRaw)?.displayName ?? "")
            line("Number", item.cardNumber)
            line("Expiry", item.cardExpiry)
            line("Issuer", item.cardIssuer)
            line("Barcode / QR", item.cardBarcode)
        }

        // Journal
        if item.isJournal || item.folder?.template == .journal {
            text += "\nDate: \(item.journalDate.formatted(date: .abbreviated, time: .shortened))"
        }

        // Generic PIN / code (cards keep it in the Card block above)
        if !item.pin.isEmpty, !(item.isCard || item.folder?.template == .cards) {
            text += "\nCode: \(item.pin)"
        }

        // Notes / body last.
        let notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { text += "\n\n\(notes)" }

        return text
    }
}
