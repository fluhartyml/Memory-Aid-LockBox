//
//  ItemDetailView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import Contacts
#endif

struct ItemDetailView: View {
    @Bindable var item: VaultItem
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var headerPhoto: PhotosPickerItem?
    @State private var showLibraryPicker = false
    @State private var showHeaderPicker = false
    @State private var showShareSheet = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var viewingImage: Data?
    @State private var capturingLocation = false
    @State private var showLocationError = false
    @State private var showAddContact = false
    @State private var contactShareFile: ShareableFile?
    @State private var isReadingContact = false

    /// This item is a secure contact card — show the contact fields + the
    /// share / add-to-Contacts actions.
    private var isContactItem: Bool {
        item.isContact || item.folder?.name == "Contacts"
    }

    /// Wraps the temp .vcf URL so it can drive `.sheet(item:)`.
    private struct ShareableFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header / hero image: the first attachment, shown as a banner
                // across the top of the note. "Set as Header" on any other photo
                // moves it here.
                if let heroData = item.imageData.first {
                    HeaderImageBanner(imageData: heroData, bias: $item.headerVerticalBias) {
                        item.dateModified = Date()
                    }
                    .contextMenu { heroMenu(for: heroData) }
                }

                // Title
                TextField("Title", text: $item.title)
                    .font(.system(size: 24, weight: .bold))
                    .textFieldStyle(.plain)

                // PIN display and copy
                if !item.pin.isEmpty {
                    pinDisplaySection
                }

                // PIN editor
                pinEditorSection

                // Notes
                notesSection

                // Secure contact card fields + share / add-to-Contacts
                if isContactItem {
                    contactSection
                }

                // Image shown large in the space below Notes
                photosSection
            }
            .padding()
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            #if os(iOS)
            ShareSheetView(item: item)
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { data in
                item.imageData.append(data)
                item.dateModified = Date()
            }
        }
        .sheet(isPresented: $showScanner) {
            DocumentScannerView { pages in
                item.imageData.append(contentsOf: pages)
                item.dateModified = Date()
            }
        }
        #endif
        // Add-to-list picker and header picker. Presented-style pickers open more
        // reliably on macOS than the button-style PhotosPicker.
        .photosPicker(isPresented: $showLibraryPicker, selection: $selectedPhoto, matching: .images)
        .photosPicker(isPresented: $showHeaderPicker, selection: $headerPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newPhoto in
            guard let newPhoto else { return }
            Task {
                await addImage(from: newPhoto, asHeader: false)
                selectedPhoto = nil   // reset so re-picking the same photo works
            }
        }
        .onChange(of: headerPhoto) { _, newPhoto in
            guard let newPhoto else { return }
            Task {
                await addImage(from: newPhoto, asHeader: true)
                headerPhoto = nil
            }
        }
        .onChange(of: item.title) { _, _ in item.dateModified = Date() }
        .onChange(of: item.notes) { _, _ in item.dateModified = Date() }
        .onChange(of: item.pin) { _, _ in item.dateModified = Date() }
        #if os(iOS)
        .sheet(item: $viewingImage) { imageData in
            ImageViewerView(imageData: imageData)
        }
        .sheet(isPresented: $showAddContact) {
            AddToContactsView(contact: buildContact()) {
                showAddContact = false
            }
        }
        .sheet(item: $contactShareFile) { file in
            ShareActivityView(items: [file.url])
        }
        .alert("Couldn't add location", isPresented: $showLocationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Location is off or unavailable. Enable it in Settings → Memory Aid LockBox → Location.")
        }
        #endif
    }

    #if os(iOS)
    /// Capture the current location as a map image (GPS embedded) and add it to
    /// the note's attachment list.
    private func captureLocation() {
        Task {
            capturingLocation = true
            if let data = await LocationMapCapture.captureCurrentLocationMap() {
                item.imageData.append(data)
                item.dateModified = Date()
            } else {
                showLocationError = true
            }
            capturingLocation = false
        }
    }
    #endif

    // MARK: - PIN Display

    private var pinDisplaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PIN / Code")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text(item.pin)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))

                Spacer()

                Button {
                    copyPINToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 18))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - PIN Editor

    private var pinEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PIN / Code")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Enter PIN or code", text: $item.pin)
                .font(.system(size: 20, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(item.folder?.name == "Cards" ? .numberPad : .default)
                #endif
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $item.notes)
                .font(.system(size: 18))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Secure contact card

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Type", selection: $item.isBusinessContact) {
                Text("Person").tag(false)
                Text("Business").tag(true)
            }
            .pickerStyle(.segmented)

            contactField("Phone", text: $item.contactPhone, systemImage: "phone")
            contactField("Email", text: $item.contactEmail, systemImage: "envelope")
            contactField("Address", text: $item.contactAddress, systemImage: "mappin.and.ellipse")

            if item.isBusinessContact {
                contactField("Website", text: $item.contactWebsite, systemImage: "globe")
                contactField("Hours", text: $item.contactHours, systemImage: "clock")
            } else {
                contactField("Relationship", text: $item.contactRelationship, systemImage: "person.2")
            }

            #if os(iOS)
            if !item.imageData.isEmpty {
                Button {
                    fillContactFromImage()
                } label: {
                    HStack(spacing: 8) {
                        if isReadingContact {
                            ProgressView()
                        } else {
                            Image(systemName: "text.viewfinder").font(.system(size: 16))
                        }
                        Text(isReadingContact ? "Reading…" : "Fill from image")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(isReadingContact)
            }

            HStack(spacing: 12) {
                Button {
                    shareContact()
                } label: {
                    Label("Share Contact Card", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showAddContact = true
                } label: {
                    Label("Add to My Contacts", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
            #endif
        }
    }

    private func contactField(_ label: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            TextField(label, text: text)
                .font(.system(size: 18))
                .textFieldStyle(.plain)
                #if os(iOS)
                .textContentType(contentType(for: label))
                .keyboardType(keyboardType(for: label))
                .autocorrectionDisabled(label != "Address")
                .textInputAutocapitalization(label == "Email" || label == "Website" ? .never : .words)
                #endif
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    #if os(iOS)
    private func contentType(for label: String) -> UITextContentType? {
        switch label {
        case "Phone": return .telephoneNumber
        case "Email": return .emailAddress
        case "Address": return .fullStreetAddress
        default: return nil
        }
    }

    private func keyboardType(for label: String) -> UIKeyboardType {
        switch label {
        case "Phone": return .phonePad
        case "Email": return .emailAddress
        default: return .default
        }
    }

    /// Build a system contact from this item's fields.
    private func buildContact() -> CNMutableContact {
        ContactCardService.makeContact(
            name: item.title,
            phone: item.contactPhone,
            email: item.contactEmail,
            address: item.contactAddress,
            isBusiness: item.isBusinessContact,
            website: item.contactWebsite
        )
    }

    /// Write the contact to a temp .vcf and present the share sheet.
    private func shareContact() {
        guard let url = ContactCardService.vCardFileURL(for: buildContact(), name: item.title) else { return }
        contactShareFile = ShareableFile(url: url)
    }

    /// Read the first attached image (e.g. a business card) with on-device OCR
    /// and fill any EMPTY contact fields — never overwrites what's already there.
    /// Uses the on-device model when available, else NSDataDetector heuristics.
    private func fillContactFromImage() {
        guard let first = item.imageData.first else { return }
        Task {
            isReadingContact = true
            defer { isReadingContact = false }

            if let card = await CardTextRecognizer.recognize(from: first),
               let smart = await CardFieldExtractor.extractContact(from: card.fullText) {
                fillContact(name: smart.name, phone: smart.phone, email: smart.email, address: smart.address)
            } else if let heur = await CardTextRecognizer.contactFields(from: first) {
                fillContact(name: heur.name ?? "", phone: heur.phone ?? "",
                            email: heur.email ?? "", address: heur.address ?? "")
            }
        }
    }

    /// Fill only the contact fields the user hasn't set yet.
    private func fillContact(name: String, phone: String, email: String, address: String) {
        if (item.title.isEmpty || item.title == "Untitled"), !name.isEmpty { item.title = name }
        if item.contactPhone.isEmpty, !phone.isEmpty { item.contactPhone = phone }
        if item.contactEmail.isEmpty, !email.isEmpty { item.contactEmail = email }
        if item.contactAddress.isEmpty, !address.isEmpty { item.contactAddress = address }
        item.dateModified = Date()
    }
    #endif

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 30) {
                Button {
                    showLibraryPicker = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 24))
                        Text("Library")
                            .font(.system(size: 14))
                    }
                }
                .buttonStyle(.plain)

                #if os(iOS)
                Button {
                    showCamera = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                        Text("Camera")
                            .font(.system(size: 14))
                    }
                }

                Button {
                    showScanner = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 24))
                        Text("Scan")
                            .font(.system(size: 14))
                    }
                }

                Button {
                    captureLocation()
                } label: {
                    VStack(spacing: 4) {
                        if capturingLocation {
                            ProgressView().frame(height: 24)
                        } else {
                            Image(systemName: "location.circle")
                                .font(.system(size: 24))
                        }
                        Text("Location")
                            .font(.system(size: 14))
                    }
                }
                .disabled(capturingLocation)
                #endif

                Spacer()
            }

            // The first image is the header banner at the top, so list the
            // remaining attachments here.
            if item.imageData.count > 1 {
                VStack(spacing: 12) {
                    ForEach(Array(item.imageData.indices.dropFirst()), id: \.self) { index in
                        photoThumbnail(at: index)
                    }
                }
            }
        }
    }

    // MARK: - Header / hero image

    @ViewBuilder
    private func heroMenu(for data: Data) -> some View {
        #if os(iOS)
        Button {
            viewingImage = data
        } label: {
            Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        #endif
        Button {
            showHeaderPicker = true
        } label: {
            Label("Replace Header Image", systemImage: "photo")
        }
        Button(role: .destructive) {
            if !item.imageData.isEmpty {
                item.imageData.removeFirst()
                item.headerVerticalBias = 0.5   // next image (if any) starts centered
                item.dateModified = Date()
            }
        } label: {
            Label("Remove Header Image", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func photoThumbnail(at index: Int) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: item.imageData[index]) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    viewingImage = item.imageData[index]
                }
                .contextMenu {
                    Button {
                        viewingImage = item.imageData[index]
                    } label: {
                        Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Button {
                        setAsHeader(index)
                    } label: {
                        Label("Set as Header", systemImage: "photo")
                    }
                    Button(role: .destructive) {
                        item.imageData.remove(at: index)
                        item.dateModified = Date()
                    } label: {
                        Label("Delete Page", systemImage: "trash")
                    }
                }
        }
        #else
        if let nsImage = NSImage(data: item.imageData[index]) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contextMenu {
                    Button {
                        setAsHeader(index)
                    } label: {
                        Label("Set as Header", systemImage: "photo")
                    }
                    Button(role: .destructive) {
                        item.imageData.remove(at: index)
                        item.dateModified = Date()
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                }
        }
        #endif
    }

    /// Move the attachment at `index` to the front so it becomes the header image.
    private func setAsHeader(_ index: Int) {
        guard item.imageData.indices.contains(index) else { return }
        let img = item.imageData.remove(at: index)
        item.imageData.insert(img, at: 0)
        item.headerVerticalBias = 0.5   // new header starts centered
        item.dateModified = Date()
    }

    /// Load a picked photo and either replace the header (index 0) or add it to
    /// the attachment list.
    @MainActor
    private func addImage(from pickerItem: PhotosPickerItem, asHeader: Bool) async {
        // An iCloud photo that isn't downloaded locally makes the first load
        // return nil (the load just starts the download) — which is why it used
        // to take two picks. Retry briefly so a single pick waits for the
        // download instead of silently skipping.
        var data: Data?
        for _ in 0..<10 {
            if let loaded = try? await pickerItem.loadTransferable(type: Data.self) {
                data = loaded
                break
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        guard let data else { return }
        if asHeader {
            if item.imageData.isEmpty {
                item.imageData.append(data)
            } else {
                item.imageData[0] = data
            }
            item.headerVerticalBias = 0.5   // new header starts centered
        } else {
            item.imageData.append(data)
        }
        item.dateModified = Date()
    }

    private func copyPINToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = item.pin
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if UIPasteboard.general.string == item.pin {
                UIPasteboard.general.string = ""
            }
        }
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.pin, forType: .string)
        #endif
    }
}

/// The note's header/hero image. When the photo is taller than the fixed banner,
/// it can be dragged vertically to choose which part shows (handy for a portrait
/// shot that lands off-center). The chosen position is saved via `bias`:
/// 0 = show the top, 0.5 = centered, 1 = show the bottom.
private struct HeaderImageBanner: View {
    let imageData: Data
    @Binding var bias: Double
    var onCommit: () -> Void

    @State private var dragAnchor: Double?
    private let bannerHeight: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let size = decodedSize
            let scale = max(width / size.width, bannerHeight / size.height)
            let overflow = max(0, size.height * scale - bannerHeight)

            Color.clear
                .frame(width: width, height: bannerHeight)
                .overlay {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: bannerHeight)
                        .offset(y: (0.5 - bias) * overflow)
                }
                .clipped()
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture()
                        .onChanged { value in
                            guard overflow > 0 else { return }
                            let start = dragAnchor ?? bias
                            if dragAnchor == nil { dragAnchor = bias }
                            bias = min(max(start - value.translation.height / overflow, 0), 1)
                        }
                        .onEnded { _ in
                            guard dragAnchor != nil else { return }
                            dragAnchor = nil
                            onCommit()
                        }
                )
        }
        .frame(height: bannerHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var decodedSize: CGSize {
        #if canImport(UIKit)
        UIImage(data: imageData)?.size ?? CGSize(width: 1, height: 1)
        #else
        NSImage(data: imageData)?.size ?? CGSize(width: 1, height: 1)
        #endif
    }

    private var image: Image {
        #if canImport(UIKit)
        Image(uiImage: UIImage(data: imageData) ?? UIImage())
        #else
        Image(nsImage: NSImage(data: imageData) ?? NSImage())
        #endif
    }
}
