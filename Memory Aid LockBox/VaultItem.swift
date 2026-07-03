//
//  VaultItem.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import Foundation
import SwiftData

@Model
final class VaultItem {
    // Defaults are required so the model can mirror to CloudKit.
    var title: String = ""
    var notes: String = ""
    var pin: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    @Attribute(.externalStorage)
    var imageData: [Data] = []

    /// Vertical framing of the header image (the first attachment) within its
    /// banner: 0 = show the top, 0.5 = centered, 1 = show the bottom. Lets a tall
    /// portrait photo be panned so the right part lands in the banner.
    /// Defaulted for CloudKit; existing notes read back as centered.
    var headerVerticalBias: Double = 0.5

    // Secure-contact fields. Used when the item is a contact card (the name is
    // the item's `title`). Empty for a normal note. All defaulted for CloudKit.
    var contactPhone: String = ""
    var contactEmail: String = ""
    var contactAddress: String = ""

    /// True when this item is a secure contact card (drives the contact UI +
    /// share/add-to-Contacts actions). Defaulted for CloudKit.
    var isContact: Bool = false

    /// True when the contact is a BUSINESS/organization rather than a person.
    /// Drives which contact fields show: a business gets Website + Hours; a
    /// person gets a Relationship label. The `title` holds the person's name or
    /// the company name accordingly. All defaulted for CloudKit.
    var isBusinessContact: Bool = false
    var contactWebsite: String = ""
    var contactHours: String = ""
    var contactRelationship: String = ""

    var folder: Folder?

    init(title: String, notes: String = "", pin: String = "", folder: Folder? = nil) {
        self.title = title
        self.notes = notes
        self.pin = pin
        self.dateCreated = Date()
        self.dateModified = Date()
        self.folder = folder
    }
}
