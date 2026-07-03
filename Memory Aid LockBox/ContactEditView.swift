//
//  ContactEditView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 7/3/26.
//
//  Specialized "New Contact" sheet for the Contacts folder — replaces the generic
//  item sheet with contact-shaped fields and a Person / Business toggle. A business
//  gets Website + Hours (e.g. store hours); a person gets a Relationship label.
//  Everything saves onto the shared VaultItem model via its additive fields.
//

import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
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

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle(isBusiness ? "New Business" : "New Contact")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 18, weight: .semibold))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
            #else
            .sheet(isPresented: $showScannerMac) {
                ScannerSheet { pages in attachedImages.append(contentsOf: pages) }
            }
            #endif
        }
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
