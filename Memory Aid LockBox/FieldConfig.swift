//
//  FieldConfig.swift
//  Memory Aid LockBox
//
//  Configure Fields (roadmap 005a/005b) — folder-level display config.
//   • 005a REMOVE: hide a template's built-in fields for this folder (reversible,
//     never deletes stored data). Stored as a set of field KEYS on the Folder.
//   • 005b ADD: user-named custom fields defined on the Folder; their per-item
//     values live on VaultItem. Built-in field NAMES are never renamed — you hide
//     them or add your own.
//

import Foundation

/// A user-added custom field definition (roadmap 005b). Lives on the Folder;
/// every item in the folder can hold a value for it (keyed by `id`).
struct CustomFieldDef: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
}

extension Folder {
    // MARK: 005a — hidden built-in fields

    var hiddenFieldKeys: Set<String> {
        get {
            guard let data = hiddenFieldsJSON.data(using: .utf8),
                  let keys = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(keys)
        }
        set {
            hiddenFieldsJSON = (try? JSONEncoder().encode(Array(newValue)))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    func isFieldHidden(_ key: String) -> Bool { hiddenFieldKeys.contains(key) }

    func setField(_ key: String, hidden: Bool) {
        var keys = hiddenFieldKeys
        if hidden { keys.insert(key) } else { keys.remove(key) }
        hiddenFieldKeys = keys
    }

    // MARK: 005b — custom field definitions

    var customFields: [CustomFieldDef] {
        get {
            guard let data = customFieldsJSON.data(using: .utf8),
                  let defs = try? JSONDecoder().decode([CustomFieldDef].self, from: data)
            else { return [] }
            return defs
        }
        set {
            customFieldsJSON = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }
}

extension VaultItem {
    /// Per-item values for the folder's custom fields (roadmap 005b), keyed by
    /// the CustomFieldDef id.
    var customValues: [String: String] {
        get {
            guard let data = customValuesJSON.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return map
        }
        set {
            customValuesJSON = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    func customValue(_ id: UUID) -> String { customValues[id.uuidString] ?? "" }

    func setCustomValue(_ value: String, for id: UUID) {
        var map = customValues
        map[id.uuidString] = value
        customValues = map
    }
}

extension FolderTemplate {
    /// The built-in fields a folder of this template can hide (roadmap 005a).
    /// The universal Title / Notes / photo are always kept (005) and not listed.
    /// `key` is stable (used in the hidden set); `label` is display-only.
    var hideableFields: [(key: String, label: String)] {
        switch self {
        case .cards:
            return [("cardNumber", "Card number"), ("cardExpiry", "Expiry"),
                    ("cardCVV", "CVN — back (3 digits)"),
                    ("cardCVVFront", "CVN — front / Amex (4 digits)"),
                    ("pin", "PIN"), ("cardIssuer", "Issuer / bank"),
                    ("cardBarcode", "Barcode / QR")]
        case .codesAccounts:
            return [("codeUsername", "Username / email"), ("codePassword", "Password"),
                    ("codeWebsite", "Website URL")]
        case .contacts:
            return [("contactPhone", "Phone"), ("contactEmail", "Email"),
                    ("contactAddress", "Address"), ("contactWebsite", "Website"),
                    ("contactHours", "Hours"), ("contactRelationship", "Source")]
        case .appointments:
            return [("apptProvider", "Provider"), ("apptPrep", "Prep / instructions"),
                    ("apptAddress", "Address"), ("apptPhone", "Phone")]
        case .receipts:
            return [("receiptAddress", "Address"), ("receiptPhone", "Phone"),
                    ("receiptSubtotal", "Subtotal"), ("receiptTax", "Tax"),
                    ("receiptTotal", "Total"), ("receiptPaymentType", "Payment type"),
                    ("receiptCardLast4", "Card last 4")]
        case .customNotes:
            return [("pin", "PIN / Code")]
        case .journal, .photos:
            return []
        }
    }
}
