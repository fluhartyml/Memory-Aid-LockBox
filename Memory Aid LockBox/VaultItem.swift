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
    /// Horizontal pan for the hero banner: 0 = show the left, 0.5 = centered,
    /// 1 = show the right. Lets a wide panorama be panned side to side.
    var headerHorizontalBias: Double = 0.5
    /// Extra zoom applied on top of the fill scale (1 = fill, up to ~4x). Pinch
    /// to zoom the hero so it can be reframed in any direction.
    var headerZoom: Double = 1.0

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

    /// The FULL imported Apple Contacts card as a raw vCard (Apple's own lossless
    /// format). When a contact is pulled in from Apple Contacts we stash the exact
    /// vCard here so nothing is dropped — every phone/email/address with its label,
    /// birthday, job, company, department, URLs, social profiles. The detail view
    /// renders every field from this, and Share / Add-to-Contacts re-export it
    /// verbatim so it lands back in Apple Contacts identically. Empty for a
    /// hand-typed contact. Defaulted for CloudKit.
    var contactVCard: String = ""

    /// True when this item is a payment/membership/ID card (drives the card UI).
    /// The card name is the item's `title`, the PIN reuses `pin`, and photos use
    /// `imageData` (front then back). All defaulted for CloudKit.
    var isCard: Bool = false
    var cardNumber: String = ""
    var cardExpiry: String = ""
    /// Security code printed on the BACK (Visa/Mastercard/Discover, 3 digits).
    var cardCVV: String = ""
    /// Security code printed on the FRONT (American Express CID, 4 digits).
    var cardCVVFront: String = ""
    var cardIssuer: String = ""
    var cardTypeRaw: String = ""
    var cardBarcode: String = ""

    /// True when this item is a login/credential (Codes / Accounts folder,
    /// roadmap 007). The service name is the item's `title`; the free-form
    /// `notes` doubles as the "Notes / 2FA" field (backup/recovery codes). All
    /// defaulted for CloudKit; empty on every other item type.
    var isCodesAccount: Bool = false
    var codeUsername: String = ""
    var codePassword: String = ""
    var codeWebsite: String = ""

    /// True when this item is a Journal entry (roadmap 009). The title/body use
    /// `title`/`notes`; the header image is `imageData.first`. `journalDate` is
    /// the entry's OWN timestamp — the timeline sorts on it (newest first) and
    /// editing an old entry never bumps it, unlike `dateModified`. All defaulted
    /// for CloudKit.
    var isJournal: Bool = false
    var journalDate: Date = Date()

    /// True when this item is an Appointment (roadmap 018). The practice/office
    /// name is the item's `title`; `apptDate` holds date+time; the card photo is
    /// `imageData`; free-form `notes` stays. "Add to Calendar/Reminders" (019)
    /// reads these. All defaulted for CloudKit.
    var isAppointment: Bool = false
    var apptProvider: String = ""
    var apptDate: Date = Date()
    var apptPrep: String = ""
    var apptAddress: String = ""
    var apptPhone: String = ""

    /// True when this item is a Receipt (roadmap 011). Store/merchant is `title`;
    /// line items are a JSON array of {name, price} in `receiptItemsJSON` (a JSON
    /// collection rather than a related model — same additive pattern the CRM log
    /// uses). "Make shopping list" (012/013) mirrors those items 1:1 into a new
    /// Reminders list. All defaulted for CloudKit.
    var isReceipt: Bool = false
    var receiptAddress: String = ""
    var receiptPhone: String = ""
    var receiptDate: Date = Date()
    var receiptItemsJSON: String = ""
    var receiptSubtotal: String = ""
    var receiptTax: String = ""
    var receiptTotal: String = ""
    var receiptPaymentType: String = ""
    var receiptCardLast4: String = ""

    /// User-added custom field values (roadmap 005b), a JSON [customFieldID:value]
    /// map keyed by the folder's CustomFieldDef ids. Additive/defaulted for
    /// CloudKit; empty on items in folders with no custom fields.
    var customValuesJSON: String = ""

    /// Contacts CRM (roadmap 010a/b/c), all on a contact item. `interactionsJSON`
    /// = the running interaction log; `significantDatesJSON` = birthdays/etc that
    /// can push to Calendar; the follow-up fields drive an opt-in overdue nudge.
    /// All JSON collections / defaulted for CloudKit.
    var interactionsJSON: String = ""
    var significantDatesJSON: String = ""
    var followUpEnabled: Bool = false
    var followUpIntervalDays: Int = 30

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
