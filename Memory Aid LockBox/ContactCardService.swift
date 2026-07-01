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

enum ContactCardService {
    /// Build a system contact from the vault item's fields (name = the title).
    static func makeContact(name: String,
                            phone: String,
                            email: String,
                            address: String) -> CNMutableContact {
        let contact = CNMutableContact()
        let (given, family) = splitName(name)
        contact.givenName = given
        contact.familyName = family

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
            contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: postal)]
        }
        return contact
    }

    /// Serialize a contact to a temporary `.vcf` file for the share sheet.
    static func vCardFileURL(for contact: CNContact, name: String) -> URL? {
        guard let data = try? CNContactVCardSerialization.data(with: [contact]) else { return nil }
        let safe = name.isEmpty ? "Contact" : name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).vcf")
        do { try data.write(to: url); return url } catch { return nil }
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
// ShareActivityView (UIActivityViewController wrapper) already lives in
// ImageViewerView.swift — reused here for the vCard share sheet.
#endif
