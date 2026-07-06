//
//  ContactCardService.swift
//  Memory Aid LockBox
//
//  Secure contact cards: an item's contact fields stay locked in the vault, but
//  can be (1) SHARED OUT as a standard .vcf vCard via the share sheet, or (2)
//  ADDED to the user's own phone Contacts via the system new-contact screen.
//  iOS/iPadOS only (ContactsUI is UIKit).
//

#if os(iOS)
import SwiftUI
import Contacts
import ContactsUI

/// One displayable line of an imported contact card (icon · label · value).
struct ContactDetailRow: Identifiable {
    let id = UUID()
    let systemImage: String
    let label: String
    let value: String
}

enum ContactCardService {
    /// Build a system contact from the vault item's fields.
    /// - For a PERSON, `name` splits into given/family.
    /// - For a BUSINESS, `name` becomes the organization name (given/family stay
    ///   blank) so Apple Contacts files it as a company — matching how the vault's
    ///   business toggle presents it. `website` maps to a work URL.
    static func makeContact(name: String,
                            phone: String,
                            email: String,
                            address: String,
                            isBusiness: Bool = false,
                            website: String = "") -> CNMutableContact {
        let contact = CNMutableContact()
        if isBusiness {
            contact.organizationName = name
        } else {
            let (given, family) = splitName(name)
            contact.givenName = given
            contact.familyName = family
        }

        if !phone.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain,
                                                   value: CNPhoneNumber(stringValue: phone))]
        }
        if !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        if !address.isEmpty {
            let postal = CNMutablePostalAddress()
            postal.street = address
            contact.postalAddresses = [CNLabeledValue(label: isBusiness ? CNLabelWork : CNLabelHome, value: postal)]
        }
        if !website.isEmpty {
            contact.urlAddresses = [CNLabeledValue(label: CNLabelWork, value: website as NSString)]
        }
        return contact
    }

    /// Serialize a contact to a temporary `.vcf` file for the share sheet.
    static func vCardFileURL(for contact: CNContact, name: String) -> URL? {
        guard let data = try? CNContactVCardSerialization.data(with: [contact]) else { return nil }
        return writeVCard(data, name: name)
    }

    /// Write already-serialized vCard TEXT to a temp `.vcf` (verbatim 1:1 export of
    /// a stored imported card — nothing rebuilt, so it round-trips exactly).
    static func vCardFileURL(fromVCard vcard: String, name: String) -> URL? {
        guard let data = vcard.data(using: .utf8) else { return nil }
        return writeVCard(data, name: name)
    }

    private static func writeVCard(_ data: Data, name: String) -> URL? {
        let safe = name.isEmpty ? "Contact" : name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).vcf")
        do { try data.write(to: url); return url } catch { return nil }
    }

    /// Serialize ANY picked contact to vCard text (Apple's exact format). Best-effort:
    /// nil if the contact lacks a key vCard serialization requires.
    static func vCardString(from contact: CNContact) -> String? {
        guard let data = try? CNContactVCardSerialization.data(with: [contact]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Parse stored vCard text back into a CNContact (for display / re-export).
    static func contact(fromVCard vcard: String) -> CNContact? {
        guard let data = vcard.data(using: .utf8),
              let contacts = try? CNContactVCardSerialization.contacts(with: data) else { return nil }
        return contacts.first
    }

    /// Every human-meaningful field of a stored vCard, ordered for display. Each
    /// property is `isKeyAvailable`-guarded so a key the vCard didn't carry can
    /// never throw. Multi-value fields (all phones/emails/addresses/URLs) are each
    /// listed with their label — the whole point of the 1:1 copy.
    static func detailRows(fromVCard vcard: String) -> [ContactDetailRow] {
        guard let c = contact(fromVCard: vcard) else { return [] }
        var rows: [ContactDetailRow] = []
        func add(_ image: String, _ label: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { return }
            rows.append(ContactDetailRow(systemImage: image, label: label, value: v))
        }
        if c.isKeyAvailable(CNContactOrganizationNameKey) { add("building.2", "Company", c.organizationName) }
        if c.isKeyAvailable(CNContactJobTitleKey) { add("briefcase", "Title", c.jobTitle) }
        if c.isKeyAvailable(CNContactDepartmentNameKey) { add("person.3", "Department", c.departmentName) }
        if c.isKeyAvailable(CNContactPhoneNumbersKey) {
            for p in c.phoneNumbers { add("phone", readableLabel(p.label, fallback: "phone"), p.value.stringValue) }
        }
        if c.isKeyAvailable(CNContactEmailAddressesKey) {
            for e in c.emailAddresses { add("envelope", readableLabel(e.label, fallback: "email"), e.value as String) }
        }
        if c.isKeyAvailable(CNContactPostalAddressesKey) {
            for a in c.postalAddresses {
                let s = CNPostalAddressFormatter.string(from: a.value, style: .mailingAddress)
                    .replacingOccurrences(of: "\n", with: ", ")
                add("mappin.and.ellipse", readableLabel(a.label, fallback: "address"), s)
            }
        }
        if c.isKeyAvailable(CNContactUrlAddressesKey) {
            for u in c.urlAddresses { add("globe", readableLabel(u.label, fallback: "url"), u.value as String) }
        }
        if c.isKeyAvailable(CNContactSocialProfilesKey) {
            for s in c.socialProfiles {
                add("at", s.value.service ?? readableLabel(s.label, fallback: "social"), s.value.username)
            }
        }
        if c.isKeyAvailable(CNContactInstantMessageAddressesKey) {
            for m in c.instantMessageAddresses {
                add("message", m.value.service ?? readableLabel(m.label, fallback: "message"), m.value.username)
            }
        }
        if c.isKeyAvailable(CNContactBirthdayKey), let b = c.birthday, let d = b.date {
            let f = DateFormatter(); f.dateFormat = (b.year == nil) ? "MMMM d" : "MMMM d, yyyy"
            add("gift", "Birthday", f.string(from: d))
        }
        if c.isKeyAvailable(CNContactDatesKey) {
            for dv in c.dates where dv.value.date != nil {
                let f = DateFormatter(); f.dateStyle = .medium
                add("calendar", readableLabel(dv.label, fallback: "date"), f.string(from: dv.value.date!))
            }
        }
        if c.isKeyAvailable(CNContactNoteKey) { add("note.text", "Note", c.note) }
        return rows
    }

    /// Human-readable label for a CNLabeledValue (e.g. "home", "work", "mobile").
    static func readableLabel(_ label: String?, fallback: String) -> String {
        guard let label, !label.isEmpty else { return fallback }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    /// Split "First Last" (or "First Middle Last") into given/family names.
    private static func splitName(_ full: String) -> (given: String, family: String) {
        let parts = full.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return (full, "") }
        return (parts.dropLast().joined(separator: " "), parts.last ?? "")
    }
}

/// Presents the system "New Contact" screen prefilled with the given contact so
/// the user can save it into their own Contacts (handles the permission prompt).
struct AddToContactsView: UIViewControllerRepresentable {
    let contact: CNMutableContact
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = context.coordinator
        controller.allowsActions = true
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func contactViewController(_ viewController: CNContactViewController,
                                   didCompleteWith contact: CNContact?) {
            onFinish()
        }
    }
}
/// Presents the system contact picker so the user can pull one of their own
/// Apple Contacts INTO the vault. Needs no Contacts permission — the picker runs
/// out of process and hands back only the single contact the user taps.
struct ContactPickerView: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }
    }
}

// ShareActivityView (UIActivityViewController wrapper) already lives in
// ImageViewerView.swift — reused here for the vCard share sheet.
#endif
