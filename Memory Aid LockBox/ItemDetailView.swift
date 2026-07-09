//
//  ItemDetailView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation
import MapKit
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import Contacts
#endif

struct ItemDetailView: View {
    @Bindable var item: VaultItem
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var headerPhoto: PhotosPickerItem?
    @State private var showLibraryPicker = false
    @State private var showHeaderPicker = false
    @State private var showShareSheet = false
    @State private var showMoveCopy = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var viewingImage: Data?
    @State private var capturingLocation = false
    @State private var showLocationError = false
    @State private var showAddContact = false
    @State private var createdContact: VaultItem?
    @State private var contactShareFile: ShareableFile?
    @State private var isReadingContact = false
    @State private var showHoursScanner = false
    @State private var showHoursLibrary = false
    @State private var hoursLibraryItem: PhotosPickerItem?
    @State private var isReadingHours = false

    /// This item is a secure contact card — show the contact fields + the
    /// share / add-to-Contacts actions.
    private var isContactItem: Bool {
        item.isContact || item.folder?.name == "Contacts"
    }

    /// This item is a card — show the card fields + Present-to-cashier.
    private var isCardItem: Bool {
        item.isCard || item.folder?.template == .cards
    }

    private var isCodesItem: Bool {
        item.isCodesAccount || item.folder?.template == .codesAccounts
    }

    private var isJournalItem: Bool {
        item.isJournal || item.folder?.template == .journal
    }

    private var isApptItem: Bool {
        item.isAppointment || item.folder?.template == .appointments
    }

    private var isReceiptItem: Bool {
        item.isReceipt || item.folder?.template == .receipts
    }

    private var isNotesItem: Bool {
        item.folder?.template == .customNotes
    }

    /// Records that offer the manual "Tag location" button (where the record was
    /// created): Notes, Journal, Receipts.
    private var showsTaggedLocation: Bool {
        isNotesItem || isJournalItem || isReceiptItem
    }

    @State private var apptStatus: String?
    @State private var receiptStatus: String?
    #if os(iOS)
    @State private var showPresentCard = false
    #endif

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
                    if isCardItem || isReceiptItem {
                        // A card or receipt scan must be shown whole, first thing —
                        // never cropped into a banner. Tap opens the full-screen
                        // pan/pinch/zoom viewer so an unreadable OCR still lets you
                        // read the receipt itself. Other pictures list at the end.
                        cardHeroImage(heroData)
                            .contextMenu { heroMenu(for: heroData) }
                    } else {
                        HeaderImageBanner(imageData: heroData,
                                          bias: $item.headerVerticalBias,
                                          hBias: $item.headerHorizontalBias,
                                          zoom: $item.headerZoom) {
                            item.dateModified = Date()
                        }
                        .contextMenu { heroMenu(for: heroData) }
                    }
                }

                // Title
                TextField("Title", text: $item.title)
                    .font(.system(size: 24, weight: .bold))
                    .textFieldStyle(.plain)

                // PIN / Code — not shown for contacts (no PIN) or cards (the card
                // section groups its own PIN field).
                if !isContactItem && !isCardItem && !isCodesItem && !isJournalItem && !isApptItem && !isReceiptItem {
                    hideable("pin") {
                        if !item.pin.isEmpty {
                            pinDisplaySection
                        }
                        pinEditorSection
                    }
                }

                // Journal entry date — editable, drives the timeline placement.
                if isJournalItem {
                    journalSection
                }

                // Appointment fields + Add to Calendar / Reminders.
                if isApptItem {
                    appointmentSection
                }

                // Receipt fields + line items + Make shopping list.
                if isReceiptItem {
                    receiptSection
                }

                // Login/credential fields (username/password/website) — above
                // Notes so "Notes / 2FA" reads as the recovery-codes home.
                if isCodesItem {
                    codesSection
                }

                // Notes
                notesSection

                // Secure contact card fields + share / add-to-Contacts
                if isContactItem {
                    contactSection
                    // CRM: interaction log · significant dates · follow-up (010a/b/c)
                    ContactCRMView(item: item)
                }

                // Card fields (number/expiry/etc.) + Present-to-cashier
                if isCardItem {
                    cardSection
                }

                // User-added custom fields (roadmap 005b), if this folder defines any.
                if let folder = item.folder, !folder.customFields.isEmpty {
                    customFieldsSection(folder)
                }

                // "Tagged location" — where the record was created (manual).
                if showsTaggedLocation {
                    taggedLocationSection
                }

                // Image shown large in the space below Notes
                photosSection
            }
            .padding()
        }
        .navigationTitle("")
        #if os(iOS)
        .fullScreenCover(isPresented: $showPresentCard) {
            PresentCardView(imageData: item.imageData.first)
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    #if os(iOS)
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    #else
                    // macOS shares the record's text summary via the standard menu.
                    ShareLink(item: RecordShare.summary(for: item)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    #endif
                    if isApptItem {
                        Button {
                            shareAppointmentICS()
                        } label: {
                            Label("Share as Calendar (.ics)", systemImage: "calendar")
                        }
                    }
                    Divider()
                    Button {
                        showMoveCopy = true
                    } label: {
                        Label("Move or Copy…", systemImage: "folder")
                    }
                } label: {
                    Label("Actions", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            #if os(iOS)
            ShareSheetView(item: item)
            #endif
        }
        .sheet(isPresented: $showMoveCopy) {
            MoveCopyView(item: item)
        }
        // "Add store to Contacts" opens straight to the new contact it created.
        .sheet(item: $createdContact) { contact in
            NavigationStack { ItemDetailView(item: contact) }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { data in
                item.imageData.append(data)
                item.dateModified = Date()
            }
            .ignoresSafeArea()
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
        .photosPicker(isPresented: $showHoursLibrary, selection: $hoursLibraryItem, matching: .images)
        .onChange(of: hoursLibraryItem) { _, it in
            guard let it else { return }
            Task {
                if let data = try? await it.loadTransferable(type: Data.self) { fillHours(from: data) }
                hoursLibraryItem = nil
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showHoursScanner) {
            DocumentScannerView { pages in if let p = pages.first { fillHours(from: p) } }
        }
        #endif
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

    /// Manual "Tag location" — capture the device's current coordinate and store
    /// it on the record (where it was created). Cross-platform (iOS + macOS).
    private func tagCurrentLocation() {
        Task {
            capturingLocation = true
            if let coord = await LocationFetcher.shared.currentCoordinate() {
                item.locationLatitude = coord.latitude
                item.locationLongitude = coord.longitude
                // Journal only: also drop a rendered map-pin picture into the
                // attachments so the spot is viewable as a plain image. Notes and
                // Receipts keep just the embedded coordinate / mini-map.
                if isJournalItem, let mapImage = await LocationMapImage.snapshotData(for: coord) {
                    item.imageData.append(mapImage)
                }
                item.dateModified = Date()
            } else {
                showLocationError = true
            }
            capturingLocation = false
        }
    }

    /// "Where this record was created" — a manual tag button, and once tagged, a
    /// tappable mini-map (→ Apple Maps). Shown on Notes / Journal / Receipts.
    @ViewBuilder
    private var taggedLocationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            if let lat = item.locationLatitude, let lon = item.locationLongitude {
                MiniMapCard(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            placeName: item.title)
                Button {
                    item.locationLatitude = nil
                    item.locationLongitude = nil
                    item.dateModified = Date()
                } label: {
                    Label("Remove location", systemImage: "trash")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            } else {
                Button {
                    tagCurrentLocation()
                } label: {
                    HStack(spacing: 8) {
                        if capturingLocation {
                            ProgressView()
                        } else {
                            Image(systemName: "mappin.and.ellipse").font(.system(size: 16))
                        }
                        Text(capturingLocation ? "Tagging…" : "Tag current location")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(capturingLocation)
            }
        }
    }

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
            Text(notesLabel)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $item.notes)
                // Receipts keep a monospaced, column-preserved layout dump.
                .font(.system(size: isReceiptItem ? 12 : 18,
                              design: isReceiptItem ? .monospaced : .default))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Card

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Type", selection: Binding(
                get: { CardType(rawValue: item.cardTypeRaw) ?? .credit },
                set: { item.cardTypeRaw = $0.rawValue }
            )) {
                ForEach(CardType.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            hideable("cardNumber") { contactField("Card number", text: $item.cardNumber, systemImage: "creditcard") }
            hideable("cardExpiry") { contactField("Expiry", text: $item.cardExpiry, systemImage: "calendar") }
            hideable("cardCVV") { contactField("CVN — back (3 digits)", text: $item.cardCVV, systemImage: "lock") }
            hideable("cardCVVFront") { contactField("CVN — front / Amex (4 digits)", text: $item.cardCVVFront, systemImage: "lock.square") }
            hideable("pin") { contactField("PIN", text: $item.pin, systemImage: "key") }
            hideable("cardIssuer") { contactField("Issuer / bank", text: $item.cardIssuer, systemImage: "building.columns") }
            hideable("cardBarcode") { contactField("Barcode / QR", text: $item.cardBarcode, systemImage: "barcode") }

            #if os(iOS)
            if !item.imageData.isEmpty {
                Button { showPresentCard = true } label: {
                    Label("Present to Cashier", systemImage: "barcode.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            #endif
        }
    }

    private var notesLabel: String {
        if isCodesItem { return "Notes / 2FA" }
        if isJournalItem { return "Body" }
        return "Notes"
    }

    // MARK: - Appointment

    private var appointmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appointment")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            hideable("apptProvider") { contactField("Provider", text: $item.apptProvider, systemImage: "person") }
            DatePicker("Date & time", selection: $item.apptDate)
                .font(.system(size: 17))
            hideable("apptPrep") { contactField("Prep / instructions", text: $item.apptPrep, systemImage: "list.clipboard") }
            hideable("apptAddress") {
                VStack(alignment: .leading, spacing: 8) {
                    contactField("Address", text: $item.apptAddress, systemImage: "mappin.and.ellipse")
                    AddressMapView(address: item.apptAddress, placeName: item.title)
                }
            }
            hideable("apptPhone") { contactField("Phone", text: $item.apptPhone, systemImage: "phone") }

            HStack(spacing: 12) {
                Button {
                    Task { await addAppointment(toReminders: false) }
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await addAppointment(toReminders: true) }
                } label: {
                    Label("Add to Reminders", systemImage: "checklist")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            if let apptStatus {
                Text(apptStatus)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addAppointment(toReminders: Bool) async {
        let title = item.title.isEmpty ? "Appointment" : item.title
        var notes = item.notes
        if !item.apptProvider.isEmpty { notes = "With \(item.apptProvider)\n\(notes)" }
        if !item.apptPhone.isEmpty { notes += "\n\(item.apptPhone)" }

        let ok: Bool
        if toReminders {
            ok = await EventKitService.addReminder(
                title: title, due: item.apptDate,
                notes: item.apptPrep.isEmpty ? notes : "Prep: \(item.apptPrep)\n\(notes)")
        } else {
            ok = await EventKitService.addEvent(
                title: title, date: item.apptDate, notes: notes,
                location: item.apptAddress, prep: item.apptPrep)
        }
        apptStatus = ok
            ? (toReminders ? "Added to Reminders." : "Added to Calendar.")
            : "Couldn't add — check Calendar/Reminders access in Settings."
    }

    /// Share OUT as a standard .ics (roadmap 023) — the system sheet offers both
    /// "Add to Calendar" and AirDrop-to-a-friend from one export.
    private func shareAppointmentICS() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        let start = f.string(from: item.apptDate)
        let end = f.string(from: item.apptDate.addingTimeInterval(3600))
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Memory Aid LockBox//EN
        BEGIN:VEVENT
        SUMMARY:\(esc(item.title.isEmpty ? "Appointment" : item.title))
        DTSTART:\(start)
        DTEND:\(end)
        LOCATION:\(esc(item.apptAddress))
        DESCRIPTION:\(esc(item.apptPrep))
        END:VEVENT
        END:VCALENDAR
        """
        let name = item.title.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name.isEmpty ? "Appointment" : name).ics")
        try? ics.data(using: .utf8)?.write(to: url)
        #if os(iOS)
        contactShareFile = ShareableFile(url: url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: - Receipt

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Receipt")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            hideable("receiptAddress") {
                VStack(alignment: .leading, spacing: 8) {
                    contactField("Address", text: $item.receiptAddress, systemImage: "mappin.and.ellipse")
                    AddressMapView(address: item.receiptAddress, placeName: item.title)
                }
            }
            hideable("receiptPhone") { contactField("Phone", text: $item.receiptPhone, systemImage: "phone") }
            DatePicker("Date & time", selection: $item.receiptDate).font(.system(size: 16))

            // Line items — editable, because OCR is unreliable and every scanned
            // line needs to be correctable after the fact. Long-press a row to
            // delete it (this is a ScrollView, so no swipe-to-delete).
            Text("Items").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(item.receiptItems.indices, id: \.self) { idx in
                HStack {
                    TextField("Item", text: lineItemBinding(idx, \.name))
                        .font(.system(size: 16))
                        #if os(iOS)
                        .autocorrectionDisabled()
                        #endif
                    Spacer()
                    TextField("Price", text: lineItemBinding(idx, \.price))
                        .font(.system(size: 16))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                .contextMenu {
                    Button(role: .destructive) { deleteReceiptItem(idx) } label: {
                        Label("Delete item", systemImage: "trash")
                    }
                }
            }
            Button { addReceiptItem() } label: {
                Label("Add item", systemImage: "plus.circle").font(.system(size: 15))
            }

            Group {
                hideable("receiptSubtotal") { receiptTotalEditRow("Subtotal", $item.receiptSubtotal) }
                hideable("receiptTax") { receiptTotalEditRow("Tax", $item.receiptTax) }
                hideable("receiptTotal") { receiptTotalEditRow("Total", $item.receiptTotal, bold: true) }
            }
            receiptTotalEditRow("Payment", $item.receiptPaymentType)
            receiptTotalEditRow("Card last 4", $item.receiptCardLast4, numeric: true)

            Button {
                Task { await makeShoppingList() }
            } label: {
                Label("Make shopping list", systemImage: "cart.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            .disabled(item.receiptItems.isEmpty)

            Button {
                Task { await addStoreToContacts() }
            } label: {
                Label("Add store to Contacts", systemImage: "person.crop.circle.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(item.title.isEmpty && item.receiptPhone.isEmpty && item.receiptAddress.isEmpty)

            if let receiptStatus {
                Text(receiptStatus).font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
    }

    /// Create a business contact in the Contacts folder from the receipt's
    /// store name, address, and phone — plus the store logo (best-effort crop
    /// from the receipt image) as the contact photo. Stores a vCard so it
    /// exports to Apple Contacts cleanly.
    private func addStoreToContacts() async {
        let store = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = store.isEmpty ? "Store" : store
        let folders = (try? modelContext.fetch(FetchDescriptor<Folder>())) ?? []
        guard let contactsFolder = folders.first(where: { $0.template == .contacts }) else {
            receiptStatus = "No Contacts folder to add the store to."
            return
        }

        let new = VaultItem(title: name, folder: contactsFolder)
        new.isBusinessContact = true
        new.contactPhone = item.receiptPhone
        new.contactAddress = item.receiptAddress

        var logoData: Data?
        if let src = item.imageData.first, let logo = await ReceiptLogoCropper.crop(from: src) {
            new.imageData = [logo]
            logoData = logo
        }

        #if os(iOS)
        let contact = ContactCardService.makeContact(
            name: name, phone: item.receiptPhone, email: "",
            address: item.receiptAddress, isBusiness: true)
        if let logoData { contact.imageData = logoData }
        new.contactVCard = ContactCardService.vCardString(from: contact) ?? ""
        #endif

        modelContext.insert(new)
        receiptStatus = "Added \(name) to Contacts\(logoData != nil ? " with its logo" : "")."
        createdContact = new   // open straight to the new store contact
    }

    /// Editable totals / payment row — label stays visible so a bare number
    /// still reads, and an empty field can be filled in when OCR missed it.
    private func receiptTotalEditRow(_ label: String, _ text: Binding<String>,
                                     bold: Bool = false, numeric: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
                #if os(iOS)
                .keyboardType(numeric ? .numberPad : .decimalPad)
                #endif
        }
        .font(.system(size: 16, weight: bold ? .semibold : .regular))
    }

    /// A binding into one line item's field that writes the whole array back
    /// (receiptItems is a computed JSON-backed property).
    private func lineItemBinding(_ idx: Int, _ keyPath: WritableKeyPath<ReceiptLineItem, String>) -> Binding<String> {
        Binding(
            get: { item.receiptItems.indices.contains(idx) ? item.receiptItems[idx][keyPath: keyPath] : "" },
            set: {
                var arr = item.receiptItems
                guard arr.indices.contains(idx) else { return }
                arr[idx][keyPath: keyPath] = $0
                item.receiptItems = arr
                item.dateModified = Date()
            }
        )
    }

    private func addReceiptItem() {
        var arr = item.receiptItems
        arr.append(ReceiptLineItem())
        item.receiptItems = arr
        item.dateModified = Date()
    }

    private func deleteReceiptItem(_ idx: Int) {
        var arr = item.receiptItems
        guard arr.indices.contains(idx) else { return }
        arr.remove(at: idx)
        item.receiptItems = arr
        item.dateModified = Date()
    }

    /// Roadmap 012/013/013a: 1:1 mirror of the line items into a NEW shopping-list
    /// Reminders list named after the receipt header, with an arrive-here alarm
    /// geocoded from the store address so it fires when you reach the store.
    private func makeShoppingList() async {
        let names = item.receiptItems.map(\.name).filter { !$0.isEmpty }
        guard !names.isEmpty else { return }

        let df = DateFormatter(); df.dateFormat = "MMM d"
        let header = "\(item.title.isEmpty ? "Receipt" : item.title) — \(df.string(from: item.receiptDate))"

        var coord: CLLocationCoordinate2D?
        if !item.receiptAddress.isEmpty,
           let request = MKGeocodingRequest(addressString: item.receiptAddress) {
            // New MapKit geocoding (iOS/macOS 26) — replaces deprecated CLGeocoder.
            coord = try? await request.mapItems.first?.location.coordinate
        }

        let ok = await EventKitService.addReminderList(
            named: header, items: names, location: coord, locationTitle: item.title)
        receiptStatus = ok
            ? "Shopping list \"\(header)\" added to Reminders\(coord == nil ? "" : " (reminds you at the store)")."
            : "Couldn't add — check Reminders access in Settings."
        if ok { openRemindersApp() }
    }

    /// Jump to Apple Reminders after building the list. iOS has no public deep
    /// link to a SPECIFIC list, so this opens the Reminders app (the new list is
    /// right there); a no-op if the scheme is unavailable.
    private func openRemindersApp() {
        #if os(iOS)
        if let url = URL(string: "x-apple-reminderkit://") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Journal

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date & time")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            DatePicker("", selection: $item.journalDate)
                .labelsHidden()
        }
    }

    // MARK: - Configure Fields (roadmap 005a/b)

    /// Hides a built-in field row when the folder has toggled it off (005a).
    @ViewBuilder
    private func hideable(_ key: String, @ViewBuilder _ content: () -> some View) -> some View {
        if !(item.folder?.isFieldHidden(key) ?? false) {
            content()
        }
    }

    /// The folder's user-added custom fields, edited per item (005b).
    private func customFieldsSection(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More fields")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(folder.customFields) { def in
                contactField(def.name, text: Binding(
                    get: { item.customValue(def.id) },
                    set: { item.setCustomValue($0, for: def.id) }
                ), systemImage: "tag")
            }
        }
    }

    // MARK: - Codes / Accounts

    private var codesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            hideable("codeUsername") { contactField("Username / email", text: $item.codeUsername, systemImage: "person") }
            hideable("codePassword") { contactField("Password", text: $item.codePassword, systemImage: "key") }
            hideable("codeWebsite") { contactField("Website URL", text: $item.codeWebsite, systemImage: "globe") }
        }
    }

    // MARK: - Secure contact card

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Type", selection: $item.isBusinessContact) {
                Text("Person").tag(false)
                Text("Business").tag(true)
            }
            .pickerStyle(.segmented)

            hideable("contactPhone") { contactField("Phone", text: $item.contactPhone, systemImage: "phone") }
            hideable("contactEmail") { contactField("Email", text: $item.contactEmail, systemImage: "envelope") }
            hideable("contactAddress") {
                VStack(alignment: .leading, spacing: 8) {
                    contactField("Address", text: $item.contactAddress, systemImage: "mappin.and.ellipse")
                    AddressMapView(address: item.contactAddress, placeName: item.title)
                }
            }

            if item.isBusinessContact {
                hideable("contactWebsite") { contactField("Website", text: $item.contactWebsite, systemImage: "globe") }
                hideable("contactHours") {
                    VStack(alignment: .leading, spacing: 6) {
                        contactField("Hours", text: $item.contactHours, systemImage: "clock")
                        hoursFillControl
                    }
                }
            } else {
                hideable("contactRelationship") { contactField("Source", text: $item.contactRelationship, systemImage: "location") }
            }

            #if os(iOS)
            fullContactCard

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
                            .font(.system(size: 18, weight: .semibold))
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
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showAddContact = true
                } label: {
                    Label("Add to My Contacts", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
            #endif
        }
    }

    #if os(iOS)
    /// The complete imported Apple Contacts card — every phone/email/address (with
    /// labels), birthday, job, company, URLs, etc., rendered read-only from the
    /// stored vCard. Only appears for contacts pulled in from Apple Contacts.
    @ViewBuilder
    private var fullContactCard: some View {
        let rows = item.contactVCard.isEmpty ? [] : ContactCardService.detailRows(fromVCard: item.contactVCard)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Full contact card")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.systemImage)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                            Text(row.value)
                                .font(.system(size: 19))
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Text("Imported from Apple Contacts — every field preserved, and it exports back identically.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 4)
        }
    }
    #endif

    private func contactField(_ label: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            TextField(label, text: text)
                .font(.system(size: 20))
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

    /// Build a system contact. Prefers the full imported vCard (1:1 — every field
    /// intact) so "Add to My Contacts" restores the complete card; falls back to
    /// the vault's primary fields for a hand-typed contact.
    private func buildContact() -> CNMutableContact {
        if !item.contactVCard.isEmpty,
           let parsed = ContactCardService.contact(fromVCard: item.contactVCard),
           let mutable = parsed.mutableCopy() as? CNMutableContact {
            return mutable
        }
        return ContactCardService.makeContact(
            name: item.title,
            phone: item.contactPhone,
            email: item.contactEmail,
            address: item.contactAddress,
            isBusiness: item.isBusinessContact,
            website: item.contactWebsite
        )
    }

    /// Write the contact to a temp .vcf and present the share sheet. Uses the stored
    /// vCard verbatim when present (perfect 1:1 round-trip), else builds from fields.
    private func shareContact() {
        let url = item.contactVCard.isEmpty
            ? ContactCardService.vCardFileURL(for: buildContact(), name: item.title)
            : ContactCardService.vCardFileURL(fromVCard: item.contactVCard, name: item.title)
        guard let url else { return }
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

    // MARK: - Store hours from a photo (door/entry sign)

    private var hoursFillControl: some View {
        Menu {
            #if os(iOS)
            Button { showHoursScanner = true } label: { Label("Scan hours sign", systemImage: "doc.viewfinder") }
            #endif
            Button { showHoursLibrary = true } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
        } label: {
            HStack(spacing: 6) {
                if isReadingHours { ProgressView() } else { Image(systemName: "text.viewfinder").font(.system(size: 15)) }
                Text(isReadingHours ? "Reading…" : "Fill Hours from photo").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
        }
        .disabled(isReadingHours)
    }

    /// OCR a door/entry hours sign and drop the hours text into the Hours field
    /// (appends if there's already text). Cross-platform (library on macOS too).
    private func fillHours(from image: Data) {
        Task {
            isReadingHours = true
            defer { isReadingHours = false }
            guard let card = await CardTextRecognizer.recognize(from: image) else { return }
            let text = hoursText(from: card.lines)
            item.contactHours = item.contactHours.isEmpty ? text : item.contactHours + "\n" + text
            item.dateModified = Date()
        }
    }

    /// Keep only lines that look like store hours (a weekday token or a clock
    /// time); fall back to all lines if the filter finds nothing.
    private func hoursText(from lines: [String]) -> String {
        let dayTokens = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN",
                         "DAILY", "HOLIDAY", "OPEN", "CLOSE", "HOUR"]
        let timeRegex = try? NSRegularExpression(
            pattern: "\\d{1,2}(:\\d{2})?\\s?(AM|PM|A|P)\\b", options: [.caseInsensitive])
        let kept = lines.filter { line in
            let u = line.uppercased()
            if dayTokens.contains(where: { u.contains($0) }) { return true }
            if let r = timeRegex {
                let range = NSRange(line.startIndex..., in: line)
                return r.firstMatch(in: line, options: [], range: range) != nil
            }
            return false
        }
        return (kept.isEmpty ? lines : kept).joined(separator: "\n")
    }

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
                #endif

                Spacer()
            }

            // The first image is the header banner at the top, so list the
            // remaining attachments here. Each row is keyed by its position and
            // handed the image Data BY VALUE — the row body never re-subscripts
            // the live `item.imageData` array. That's deliberate: subscripting by
            // a stored index inside the row crashes ("index out of range") the
            // instant a page is deleted, because SwiftUI briefly re-renders the
            // disappearing row with an index the shrunken array no longer has.
            if item.imageData.count > 1 {
                VStack(spacing: 12) {
                    ForEach(Array(item.imageData.enumerated().dropFirst()), id: \.offset) { offset, data in
                        photoThumbnail(data: data, at: offset)
                    }
                }
            }
        }
    }

    // MARK: - Header / hero image

    /// The first card attachment shown whole (not cropped) at the top of the
    /// detail. Tap to view full size.
    @ViewBuilder
    private func cardHeroImage(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { viewingImage = data }
        }
        #else
        if let ns = NSImage(data: data) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        #endif
    }

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

    /// One attachment row. `data` is the image bytes handed in by value (used for
    /// display and full-size view); `index` is only read at the moment a menu
    /// action fires, and every array mutation is bounds-guarded so a stale index
    /// can never crash.
    @ViewBuilder
    private func photoThumbnail(data: Data, at index: Int) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    viewingImage = data
                }
                .contextMenu {
                    Button {
                        viewingImage = data
                    } label: {
                        Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Button {
                        setAsHeader(index)
                    } label: {
                        Label("Set as Header", systemImage: "photo")
                    }
                    Button(role: .destructive) {
                        deleteAttachment(at: index)
                    } label: {
                        Label("Delete Page", systemImage: "trash")
                    }
                }
        }
        #else
        if let nsImage = NSImage(data: data) {
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
                        deleteAttachment(at: index)
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                }
        }
        #endif
    }

    /// Remove the attachment at `index`, bounds-checked. Guarding here (rather
    /// than a bare `remove(at:)`) is what makes deleting a page safe even if the
    /// row's captured index is momentarily out of step with the array.
    private func deleteAttachment(at index: Int) {
        guard item.imageData.indices.contains(index) else { return }
        item.imageData.remove(at: index)
        item.dateModified = Date()
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
    @Binding var bias: Double            // vertical: 0 top … 1 bottom
    @Binding var hBias: Double           // horizontal: 0 left … 1 right
    @Binding var zoom: Double            // extra scale on top of fill (>= 1)
    var onCommit: () -> Void

    @State private var dragAnchor: CGPoint?
    @State private var zoomAnchor: Double?
    private let bannerHeight: CGFloat = 380
    private let maxZoom: Double = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let size = decodedSize
            // Fill the banner, then apply the user's pinch zoom on top.
            let fill = max(width / size.width, bannerHeight / size.height)
            let scale = fill * max(1, zoom)
            let scaledW = size.width * scale
            let scaledH = size.height * scale
            let overflowX = max(0, scaledW - width)
            let overflowY = max(0, scaledH - bannerHeight)

            Color.clear
                .frame(width: width, height: bannerHeight)
                .overlay {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: bannerHeight)
                        .scaleEffect(max(1, zoom), anchor: .center)
                        .offset(x: (0.5 - hBias) * overflowX,
                                y: (0.5 - bias) * overflowY)
                }
                .clipped()
                .contentShape(Rectangle())
                .highPriorityGesture(
                    // Drag pans in whichever axis has room (left/right for a wide
                    // panorama, up/down for a tall portrait); pinch zooms to reframe.
                    // Both share high priority so either wins over the page scroll —
                    // pinch as a mere simultaneous gesture got swallowed by the drag
                    // on a normal photo that had vertical pan room.
                    DragGesture()
                        .onChanged { value in
                            if dragAnchor == nil { dragAnchor = CGPoint(x: hBias, y: bias) }
                            let start = dragAnchor ?? CGPoint(x: hBias, y: bias)
                            if overflowX > 0 {
                                hBias = min(max(start.x - value.translation.width / overflowX, 0), 1)
                            }
                            if overflowY > 0 {
                                bias = min(max(start.y - value.translation.height / overflowY, 0), 1)
                            }
                        }
                        .onEnded { _ in
                            guard dragAnchor != nil else { return }
                            dragAnchor = nil
                            onCommit()
                        }
                        .simultaneously(with:
                            MagnificationGesture()
                                .onChanged { value in
                                    if zoomAnchor == nil { zoomAnchor = zoom }
                                    let base = zoomAnchor ?? zoom
                                    zoom = min(max(base * value, 1), maxZoom)
                                }
                                .onEnded { _ in
                                    zoomAnchor = nil
                                    onCommit()
                                }
                        )
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

#if os(iOS)
/// Full-screen, max-brightness view of a card photo for presenting at a
/// register (roadmap 006a). Boosts screen brightness on appear and restores it
/// on dismiss so a scanner can read the barcode off the glass.
private struct PresentCardView: View {
    @Environment(\.dismiss) private var dismiss
    let imageData: Data?
    /// The brightness to restore on dismiss. Optional so we only ever restore a
    /// value we actually captured — if no screen was available we leave it be.
    @State private var priorBrightness: CGFloat?

    /// The current screen via the active window scene — the iOS 26 replacement
    /// for the deprecated global `UIScreen.main`.
    private var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let imageData, let ui = UIImage(data: imageData) {
                Image(uiImage: ui).resizable().scaledToFit().padding()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.gray)
                            .padding()
                    }
                }
                Spacer()
                Text("Hold up to the scanner")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            if let screen = activeScreen {
                priorBrightness = screen.brightness
                screen.brightness = 1.0
            }
        }
        .onDisappear {
            if let prior = priorBrightness, let screen = activeScreen {
                screen.brightness = prior
            }
        }
    }
}
#endif
