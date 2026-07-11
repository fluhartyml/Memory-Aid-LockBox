//
//  CodesAccountsEditView.swift
//  Memory Aid LockBox
//
//  The specialized create sheet for the Codes / Accounts folder (roadmap 007) —
//  the passwords core. Fields: Service name · Username/email · Password ·
//  Website URL · Notes/2FA. Sensitive values show in PLAIN TEXT (roadmap 003 —
//  the vault is the mask, via Face ID + auto-lock). The free-form notes field is
//  labeled "Notes / 2FA" so backup/recovery codes have an obvious home. "Fill
//  from image" scans a screenshot/label and fills empty fields (roadmap 004);
//  an optional photo is kept per roadmap 005. Mirrors CardEditView's structure.
//

import SwiftUI
import SwiftData
import PhotosUI

struct CodesAccountsEditView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var service = ""
    @State private var username = ""
    @State private var password = ""
    @State private var website = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []

    @State private var libraryItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var pendingFillAfterScan = false
    @State private var activeSheet: CodesSheet?
    #if os(macOS)
    @State private var showScannerMac = false
    #endif

    private enum CodesSheet: Int, Identifiable {
        case scanner, camera
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Account name", $service)
                } header: {
                    Text("Account").font(.system(size: 16))
                }

                Section {
                    field("Username / email", $username)
                    field("Password", $password)
                    field("Website URL", $website)
                } header: {
                    Text("Credentials").font(.system(size: 16))
                } footer: {
                    Text("Shown in plain text — the vault itself is the lock (Face ID + auto-lock).")
                        .font(.system(size: 13))
                }

                Section {
                    TextEditor(text: $notes)
                        .font(.system(size: 18))
                        .frame(minHeight: 100)
                } header: {
                    Text("Notes / 2FA").font(.system(size: 16))
                } footer: {
                    Text("Paste backup / recovery codes or 2FA details here.")
                        .font(.system(size: 13))
                }

                Section {
                    if !attachedImages.isEmpty { imageArea }
                    fillFromImageButton
                    captureButtons
                } header: {
                    Text("Photo").font(.system(size: 16))
                } footer: {
                    Text("\"Fill from image\" scans a screenshot or label and fills any empty fields with on-device text recognition.")
                        .font(.system(size: 13))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 640)
            #endif
            .resizingNavigationTitle("New Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 18, weight: .semibold))
                        .disabled(service.isEmpty && username.isEmpty)
                }
            }
            #if os(iOS)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .scanner:
                    DocumentScannerView { pages in
                        attachedImages.append(contentsOf: pages)
                        if pendingFillAfterScan {
                            pendingFillAfterScan = false
                            if let scanned = pages.first { fillFromImage(from: scanned) }
                        }
                    }
                case .camera:
                    CameraCaptureView { data in attachedImages.append(data) }
                }
            }
            #else
            .sheet(isPresented: $showScannerMac) {
                ScannerSheet { pages in
                    attachedImages.append(contentsOf: pages)
                    if pendingFillAfterScan {
                        pendingFillAfterScan = false
                        if let scanned = pages.first { fillFromImage(from: scanned) }
                    }
                }
            }
            #endif
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        attachedImages.append(data)
                    }
                    libraryItem = nil
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        TextField(label, text: text)
            .font(.system(size: 18))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
    }

    // MARK: - Photos

    private var imageArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachedImages.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        thumbnail(at: index)
                        Button(role: .destructive) { attachedImages.remove(at: index) } label: {
                            Image(systemName: "trash").font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func thumbnail(at index: Int) -> some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: attachedImages[index]) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #else
        if let ns = NSImage(data: attachedImages[index]) {
            Image(nsImage: ns).resizable().scaledToFill()
                .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #endif
    }

    private var captureButtons: some View {
        HStack(spacing: 28) {
            #if os(iOS)
            captureButton("Scan", "doc.viewfinder") { activeSheet = .scanner }
            captureButton("Camera", "camera") { activeSheet = .camera }
            #else
            captureButton("Scan", "scanner") { showScannerMac = true }
            #endif
            PhotosPicker(selection: $libraryItem, matching: .images) {
                captureLabel("Library", "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func captureButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { captureLabel(title, symbol) }.buttonStyle(.plain)
    }

    private func captureLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(title).font(.system(size: 13))
        }
        .foregroundStyle(Color.accentColor)
    }

    private var fillFromImageButton: some View {
        Button {
            pendingFillAfterScan = true
            #if os(iOS)
            activeSheet = .scanner
            #else
            showScannerMac = true
            #endif
        } label: {
            HStack(spacing: 8) {
                if isReading { ProgressView() }
                else { Image(systemName: "text.viewfinder").font(.system(size: 18)) }
                Text(isReading ? "Reading…" : "Fill from image").font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(isReading)
    }

    // MARK: - Fill from image

    private func fillFromImage(from image: Data? = nil) {
        guard let first = image ?? attachedImages.first else { return }
        Task {
            isReading = true
            defer { isReading = false }
            guard let card = await CardTextRecognizer.recognize(from: first) else { return }
            let text = card.fullText
            // Credentials don't OCR into discrete fields reliably, so the raw
            // recognized text lands in Notes / 2FA (the recovery-codes home);
            // a suggested title fills the service name when it's still empty.
            if service.isEmpty, let suggested = card.suggestedTitle { service = suggested }
            if notes.isEmpty { notes = text }
        }
    }

    // MARK: - Save

    private func save() {
        let item = VaultItem(title: service.isEmpty ? "Untitled Account" : service,
                             notes: notes,
                             folder: folder)
        item.isCodesAccount = true
        item.codeUsername = username
        item.codePassword = password
        item.codeWebsite = website
        item.imageData = attachedImages
        modelContext.insert(item)
        dismiss()
    }
}
