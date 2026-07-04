//
//  ContactEditView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 7/3/26.
//
//  Specialized "New Contact" sheet for the Contacts folder — replaces the generic
//  item sheet with contact-shaped fields and a Person / Business toggle. A business
//  gets Website + Hours (e.g. store hours); a person gets a Relationship label.
//
//  Also hosts SELF-SERVE mode: hand the phone to a guest so they enter their own
//  info + a selfie, on a stripped screen with no route to the vault. Exiting the
//  mode requires a Face ID challenge (owner). For a true hardware lock the owner
//  uses Guided Access (a system feature) — the app can only coach it, not force it.
//

import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import Contacts
#endif

struct ContactEditView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isBusiness = false
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var website = ""
    @State private var hours = ""
    @State private var relationship = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []

    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showScannerMac = false
    @State private var isReadingContact = false
    @State private var showContactPicker = false

    // Self-serve (hand-to-guest) mode
    @State private var isSelfServe = false
    @State private var showSelfieCamera = false
    @State private var isVerifying = false

    private var navTitle: String {
        isSelfServe ? "Self-Serve" : (isBusiness ? "New Business" : "New Contact")
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(isSelfServe)
                #endif
                .toolbar {
                    if !isSelfServe {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }.font(.system(size: 18))
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { save() }
                                .font(.system(size: 18, weight: .semibold))
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .onChange(of: libraryItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            attachedImages.append(data)
                        }
                        libraryItem = nil
                    }
                }
                #if os(iOS)
                .sheet(isPresented: $showCamera) {
                    CameraCaptureView { data in attachedImages.append(data) }
                }
                .sheet(isPresented: $showScanner) {
                    DocumentScannerView { pages in attachedImages.append(contentsOf: pages) }
                }
                .sheet(isPresented: $showSelfieCamera) {
                    CameraCaptureView(preferFrontCamera: true) { data in
                        if attachedImages.isEmpty { attachedImages.insert(data, at: 0) }
                        else { attachedImages[0] = data }
                    }
                }
                .sheet(isPresented: $showContactPicker) {
                    ContactPickerView { importContact($0) }
                }
                #else
                .sheet(isPresented: $showScannerMac) {
                    ScannerSheet { pages in attachedImages.append(contentsOf: pages) }
                }
                #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if isSelfServe { selfServeIntake } else { normalForm }
        #else
        normalForm
        #endif
    }

    // MARK: - Normal form

    private var normalForm: some View {
        Form {
            #if os(iOS)
            Section {
                Button {
                    showContactPicker = true
                } label: {
                    Label("Import from Apple Contacts", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 18))
                }
                Button {
                    isBusiness = false          // guests are people
                    isSelfServe = true
                } label: {
                    Label("Hand to Guest (Self-Serve)", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 18))
                }
            } footer: {
                Text("Start from scratch below, pull one of your Apple Contacts in (with their photo), or hand the phone to a guest to enter their own info.")
                    .font(.system(size: 13))
            }
            #endif

            Section {
                Picker("Type", selection: $isBusiness) {
                    Text("Person").tag(false)
                    Text("Business").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField(isBusiness ? "Company name" : "Full name", text: $name)
                    .font(.system(size: 18))
                    #if os(iOS)
                    .textContentType(isBusiness ? .organizationName : .name)
                    .textInputAutocapitalization(.words)
                    #endif
            } header: {
                Text(isBusiness ? "Company" : "Name").font(.system(size: 16))
            }

            Section {
                contactField("Phone", text: $phone, systemImage: "phone")
                contactField("Email", text: $email, systemImage: "envelope")
                contactField("Address", text: $address, systemImage: "mappin.and.ellipse")
                if isBusiness {
                    contactField("Website", text: $website, systemImage: "globe")
                    contactField("Hours", text: $hours, systemImage: "clock")
                } else {
                    contactField("Relationship", text: $relationship, systemImage: "person.2")
                }
            } header: {
                Text("Details").font(.system(size: 16))
            }

            Section {
                TextEditor(text: $notes)
                    .font(.system(size: 18))
                    .frame(minHeight: 80)
            } header: {
                Text("Notes").font(.system(size: 16))
            }

            Section {
                captureButtons
                if !attachedImages.isEmpty {
                    fillFromImageButton
                    imageArea
                }
            } header: {
                Text(isBusiness ? "Logo / Card" : "Photo / Card").font(.system(size: 16))
            } footer: {
                if !attachedImages.isEmpty {
                    Text("\"Fill from image\" reads a business card with on-device text recognition and fills any empty fields.")
                        .font(.system(size: 13))
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    // MARK: - Capture

    private var captureButtons: some View {
        HStack(spacing: 28) {
            #if os(iOS)
            captureButton("Scan", systemImage: "doc.viewfinder") { showScanner = true }
            captureButton("Camera", systemImage: "camera") { showCamera = true }
            #else
            captureButton("Scan", systemImage: "scanner") { showScannerMac = true }
            #endif
            PhotosPicker(selection: $libraryItem, matching: .images) {
                captureLabel("Library", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func captureButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { captureLabel(title, systemImage: systemImage) }.buttonStyle(.plain)
    }

    private func captureLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 24))
            Text(title).font(.system(size: 14))
        }
        .foregroundStyle(Color.accentColor)
    }

    private func contactField(_ label: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 22)
            TextField(label, text: text)
                .font(.system(size: 18))
                #if os(iOS)
                .keyboardType(keyboardType(for: label))
                .textContentType(contentType(for: label))
                .autocorrectionDisabled(label == "Email" || label == "Website")
                .textInputAutocapitalization(label == "Email" || label == "Website" ? .never : .words)
                #endif
        }
    }

    #if os(iOS)
    private func contentType(for label: String) -> UITextContentType? {
        switch label {
        case "Phone": return .telephoneNumber
        case "Email": return .emailAddress
        case "Address": return .fullStreetAddress
        case "Website": return .URL
        default: return nil
        }
    }

    private func keyboardType(for label: String) -> UIKeyboardType {
        switch label {
        case "Phone": return .phonePad
        case "Email": return .emailAddress
        case "Website": return .URL
        default: return .default
        }
    }
    #endif

    // MARK: - Fill from image (on-device OCR)

    private var fillFromImageButton: some View {
        Button { fillFromImage() } label: {
            HStack(spacing: 8) {
                if isReadingContact { ProgressView() }
                else { Image(systemName: "text.viewfinder").font(.system(size: 18)) }
                Text(isReadingContact ? "Reading…" : "Fill from image").font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(isReadingContact)
    }

    @ViewBuilder
    private var imageArea: some View {
        VStack(spacing: 12) {
            ForEach(attachedImages.indices, id: \.self) { index in
                image(at: index)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func image(at index: Int) -> some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: attachedImages[index]) {
            Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contextMenu { removeButton(at: index) }
        }
        #else
        if let ns = NSImage(data: attachedImages[index]) {
            Image(nsImage: ns).resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contextMenu { removeButton(at: index) }
        }
        #endif
    }

    private func removeButton(at index: Int) -> some View {
        Button(role: .destructive) { attachedImages.remove(at: index) } label: {
            Label("Remove Image", systemImage: "trash")
        }
    }

    /// Read the first attached image with on-device OCR and fill any EMPTY fields.
    private func fillFromImage() {
        guard let first = attachedImages.first else { return }
        Task {
            isReadingContact = true
            defer { isReadingContact = false }
            #if os(iOS)
            if let card = await CardTextRecognizer.recognize(from: first),
               let smart = await CardFieldExtractor.extractContact(from: card.fullText) {
                fill(name: smart.name, phone: smart.phone, email: smart.email, address: smart.address)
            } else if let heur = await CardTextRecognizer.contactFields(from: first) {
                fill(name: heur.name ?? "", phone: heur.phone ?? "", email: heur.email ?? "", address: heur.address ?? "")
            }
            #else
            if let card = await CardTextRecognizer.recognize(from: first) {
                if name.isEmpty, let s = card.suggestedTitle { name = s }
                if notes.isEmpty { notes = card.fullText }
            }
            #endif
        }
    }

    private func fill(name n: String, phone p: String, email e: String, address a: String) {
        if name.isEmpty, !n.isEmpty { name = n }
        if phone.isEmpty, !p.isEmpty { phone = p }
        if email.isEmpty, !e.isEmpty { email = e }
        if address.isEmpty, !a.isEmpty { address = a }
    }

    // MARK: - Import from Apple Contacts

    #if os(iOS)
    /// Pull a picked Apple Contact into the fields (+ its photo). Auto-selects the
    /// Business toggle when the contact is a company (organization, no person name).
    /// Every property is guarded with `isKeyAvailable` so an un-fetched key can
    /// never throw.
    private func importContact(_ c: CNContact) {
        let org = c.isKeyAvailable(CNContactOrganizationNameKey)
            ? c.organizationName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        var full = ""
        if c.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]) {
            full = CNContactFormatter.string(from: c, style: .fullName) ?? ""
        }
        if full.isEmpty, !org.isEmpty {
            isBusiness = true
            name = org
        } else {
            isBusiness = false
            name = full.isEmpty ? org : full
        }
        if c.isKeyAvailable(CNContactPhoneNumbersKey), let p = c.phoneNumbers.first {
            phone = p.value.stringValue
        }
        if c.isKeyAvailable(CNContactEmailAddressesKey), let e = c.emailAddresses.first {
            email = e.value as String
        }
        if c.isKeyAvailable(CNContactPostalAddressesKey), let postal = c.postalAddresses.first?.value {
            address = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
        }
        if c.isKeyAvailable(CNContactUrlAddressesKey), let url = c.urlAddresses.first {
            website = url.value as String
        }
        // Pull the contact's photo in as the first attachment (becomes the header).
        if c.isKeyAvailable(CNContactImageDataKey), let img = c.imageData {
            attachedImages.insert(img, at: 0)
        } else if c.isKeyAvailable(CNContactThumbnailImageDataKey), let thumb = c.thumbnailImageData {
            attachedImages.insert(thumb, at: 0)
        }
    }
    #endif

    // MARK: - Self-serve (hand to guest)

    #if os(iOS)
    private var selfServeIntake: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !UIAccessibility.isGuidedAccessEnabled {
                    guidedAccessTip
                }

                VStack(spacing: 6) {
                    Text("Add Your Contact Info")
                        .font(.system(size: 26, weight: .bold))
                    Text("Enter your details and take a selfie, then hand the phone back.")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                selfieArea

                VStack(spacing: 12) {
                    guestField("Full name", text: $name, systemImage: "person")
                    guestField("Phone", text: $phone, systemImage: "phone")
                    guestField("Email", text: $email, systemImage: "envelope")
                }

                Button {
                    returnToOwner()
                } label: {
                    HStack(spacing: 8) {
                        if isVerifying { ProgressView().tint(.white) }
                        else { Image(systemName: "faceid").font(.system(size: 18)) }
                        Text("Done — Return to Owner").font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isVerifying)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    private var guidedAccessTip: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 18))
            Text("Owner: triple-click the side button to lock the phone to this screen (Guided Access).")
                .font(.system(size: 13))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var selfieArea: some View {
        VStack(spacing: 10) {
            if let first = attachedImages.first, let ui = UIImage(data: first) {
                Image(uiImage: ui).resizable().scaledToFill()
                    .frame(width: 160, height: 160).clipShape(Circle())
            } else {
                Circle().fill(.quaternary).frame(width: 160, height: 160)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 64)).foregroundStyle(.secondary))
            }
            Button {
                showSelfieCamera = true
            } label: {
                Label(attachedImages.isEmpty ? "Take Selfie" : "Retake Selfie", systemImage: "camera")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private func guestField(_ placeholder: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 26)
            TextField(placeholder, text: text)
                .font(.system(size: 20))
                .keyboardType(placeholder == "Phone" ? .phonePad : (placeholder == "Email" ? .emailAddress : .default))
                .textContentType(placeholder == "Phone" ? .telephoneNumber : (placeholder == "Email" ? .emailAddress : .name))
                .textInputAutocapitalization(placeholder == "Email" ? .never : .words)
                .autocorrectionDisabled(placeholder == "Email")
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Owner takes the phone back: a Face ID challenge exits self-serve mode and
    /// returns to the normal form (with the guest's info filled in for review).
    private func returnToOwner() {
        Task {
            isVerifying = true
            let ok = await BiometricAuthenticator.authenticate(reason: "Return control to the owner")
            isVerifying = false
            if ok {
                isBusiness = false
                isSelfServe = false
            }
        }
    }
    #endif

    // MARK: - Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let item = VaultItem(title: trimmed.isEmpty ? "Untitled" : trimmed, notes: notes, folder: folder)
        item.isContact = true
        item.isBusinessContact = isBusiness
        item.contactPhone = phone
        item.contactEmail = email
        item.contactAddress = address
        item.contactWebsite = isBusiness ? website : ""
        item.contactHours = isBusiness ? hours : ""
        item.contactRelationship = isBusiness ? "" : relationship
        item.imageData = attachedImages
        modelContext.insert(item)
        dismiss()
    }
}
