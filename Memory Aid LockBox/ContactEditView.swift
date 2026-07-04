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
    @Environment(VaultLock.self) private var vaultLock
    @AppStorage("autoLockMinutes") private var autoLockMinutes = 5

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
    // The MediaAsset created when a self-serve selfie is saved to the media
    // library; kept so a retake updates it instead of adding a duplicate.
    @State private var selfieMediaAsset: MediaAsset?

    @State private var libraryItem: PhotosPickerItem?
    @State private var isReadingContact = false

    // Self-serve (hand-to-guest) mode
    @State private var isSelfServe = false
    @State private var isVerifying = false
    // After the owner's Face ID passes, we can't programmatically end Guided Access
    // (system feature) — so we lock the vault and show an instruction screen that
    // tells the owner to triple-click and turn it off.
    @State private var showExitGuidedAccess = false
    @State private var didLockOnExit = false

    // A SINGLE modal channel. Multiple `.sheet(isPresented:)` modifiers stacked on
    // one view can silently drop a sheet's result (that's why the selfie wasn't
    // landing); `.sheet(item:)` with one enum is the reliable pattern.
    #if os(iOS)
    @State private var activeSheet: ContactSheet?
    private enum ContactSheet: Int, Identifiable {
        case scanner, camera, selfie, contactPicker
        var id: Int { rawValue }
    }
    #else
    @State private var showScannerMac = false
    #endif

    private var navTitle: String {
        if showExitGuidedAccess { return "Return to Owner" }
        return isSelfServe ? "Self-Serve" : (isBusiness ? "New Business" : "New Contact")
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(isSelfServe || showExitGuidedAccess)
                #endif
                .toolbar {
                    if !isSelfServe && !showExitGuidedAccess {
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
                // Pause the vault auto-lock while entering a contact — otherwise the
                // timer fires mid-entry, ejects to the folder list, and the unsaved
                // card is lost (critical for the hand-to-guest flow). Re-arms from
                // now when the sheet closes.
                .onAppear { vaultLock.unlock(forMinutes: 0) }
                .onDisappear {
                    // Re-arm the normal auto-lock UNLESS we deliberately locked on
                    // the way out (return-to-owner) — otherwise we'd re-unlock it.
                    if !didLockOnExit { vaultLock.unlock(forMinutes: autoLockMinutes) }
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
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .scanner:
                        DocumentScannerView { pages in attachedImages.append(contentsOf: pages) }
                    case .camera:
                        CameraCaptureView { data in attachedImages.append(data) }
                    case .selfie:
                        // Dedicated AVCapture front-camera view — UIImagePickerController
                        // fails to force the front camera on iOS 27 / 16-series.
                        SelfieCaptureView { data in
                            if attachedImages.isEmpty { attachedImages.insert(data, at: 0) }
                            else { attachedImages[0] = data }
                            saveSelfieToMedia(data)
                        }
                    case .contactPicker:
                        ContactPickerView { importContact($0) }
                    }
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
        if showExitGuidedAccess { exitGuidedAccessScreen }
        else if isSelfServe { selfServeIntake }
        else { normalForm }
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
                    activeSheet = .contactPicker
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
                if !attachedImages.isEmpty {
                    imageArea
                    fillFromImageButton
                }
                captureButtons
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
            captureButton("Scan", systemImage: "doc.viewfinder") { activeSheet = .scanner }
            captureButton("Camera", systemImage: "camera") { activeSheet = .camera }
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
                activeSheet = .selfie
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

    /// Owner takes the phone back: a Face ID challenge exits self-serve and, if the
    /// guest entered a name, auto-saves the card immediately (a successful scan
    /// commits it — nothing lost if Save isn't tapped). The app can't end Guided
    /// Access itself, so it hands off to the exit-instruction screen.
    private func returnToOwner() {
        Task {
            isVerifying = true
            let ok = await BiometricAuthenticator.authenticate(reason: "Return control to the owner")
            isVerifying = false
            guard ok else { return }
            isBusiness = false
            isSelfServe = false
            if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                persist()
            }
            showExitGuidedAccess = true
        }
    }

    /// Shown after the owner authenticates: the vault stays on-screen with a saved
    /// card, and the owner is told to physically turn off Guided Access. Tapping
    /// Done locks the vault and dismisses back to the (locked) folder list.
    private var exitGuidedAccessScreen: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72)).foregroundStyle(.tint)
            Text("Contact Saved").font(.system(size: 28, weight: .bold))
            VStack(alignment: .leading, spacing: 16) {
                exitStep(1, "Triple-click the side button", systemImage: "s.circle")
                exitStep(2, "Tap “End”, then enter your Guided Access passcode", systemImage: "lock.open")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("This turns off Guided Access so only you can use the rest of the phone.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                didLockOnExit = true
                vaultLock.lockNow()
                dismiss()
            } label: {
                Text("Done — Lock the Vault")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func exitStep(_ number: Int, _ text: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
            Text(text).font(.system(size: 17))
            Spacer(minLength: 0)
            Image(systemName: systemImage).font(.system(size: 20)).foregroundStyle(.secondary)
        }
    }
    #endif

    // MARK: - Save

    private func save() {
        persist()
        dismiss()
    }

    /// Insert the card into the vault without dismissing (return-to-owner needs to
    /// save, then show the Guided-Access exit screen rather than close).
    private func persist() {
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
    }

    /// Also save the self-serve selfie into the actual LockBox Photos folder —
    /// the media library the user browses — so it lands in that media grid, not
    /// only as the contact's photo. A retake updates the same asset instead of
    /// duplicating.
    private func saveSelfieToMedia(_ data: Data) {
        let thumb = MediaThumbnailer.photoThumbnail(from: data)
        if let existing = selfieMediaAsset {
            existing.data = data
            existing.thumbnailData = thumb
            return
        }
        // The real Photos folder, by name; fall back to the media-library
        // (photos-template) folder if it was renamed.
        let folders = (try? modelContext.fetch(FetchDescriptor<Folder>())) ?? []
        guard let photosFolder = folders.first(where: { $0.name == "Photos" })
                ?? folders.first(where: { $0.template == .photos }) else { return }
        let asset = MediaAsset(type: .photo,
                               data: data,
                               thumbnailData: thumb,
                               originalFileName: "Selfie.jpg",
                               folder: photosFolder)
        modelContext.insert(asset)
        selfieMediaAsset = asset
    }
}
