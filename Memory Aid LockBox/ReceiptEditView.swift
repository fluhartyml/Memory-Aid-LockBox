//
//  ReceiptEditView.swift
//  Memory Aid LockBox
//
//  The specialized create sheet for the Receipts template (roadmap 011). Fields:
//  Store/merchant (title) · Address · Phone · Date/time · Line items (discrete
//  name+price rows) · Subtotal/Tax/Total · Payment (type + card last-4) · Receipt
//  photo · Notes. Line items are discrete rows so "Make grocery list" (012/013)
//  can mirror them 1:1 into a new Reminders list. Values show plain text (003).
//

import SwiftUI
import SwiftData
import PhotosUI

/// One receipt line: a name and a price, kept as strings for free-form entry.
struct ReceiptLineItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var price: String = ""
}

extension VaultItem {
    /// The receipt's line items, decoded from / encoded to `receiptItemsJSON`.
    var receiptItems: [ReceiptLineItem] {
        get {
            guard let data = receiptItemsJSON.data(using: .utf8),
                  let items = try? JSONDecoder().decode([ReceiptLineItem].self, from: data)
            else { return [] }
            return items
        }
        set {
            receiptItemsJSON = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }
}

struct ReceiptEditView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var store = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var date = Date()
    @State private var lineItems: [ReceiptLineItem] = [ReceiptLineItem()]
    @State private var subtotal = ""
    @State private var tax = ""
    @State private var total = ""
    @State private var paymentType = ""
    @State private var cardLast4 = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []

    @State private var libraryItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var pendingFillAfterScan = false
    @State private var activeSheet: ReceiptSheet?
    #if os(macOS)
    @State private var showScannerMac = false
    #endif

    private enum ReceiptSheet: Int, Identifiable {
        case scanner, camera
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Store / merchant", $store)
                    field("Address", $address)
                    field("Phone", $phone)
                    DatePicker("Date & time", selection: $date).font(.system(size: 17))
                } header: {
                    Text("Receipt").font(.system(size: 16))
                }

                Section {
                    ForEach($lineItems) { $item in
                        HStack {
                            TextField("Item", text: $item.name).font(.system(size: 17))
                            Spacer()
                            TextField("Price", text: $item.price)
                                .font(.system(size: 17))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                    .onDelete { lineItems.remove(atOffsets: $0) }
                    Button {
                        lineItems.append(ReceiptLineItem())
                    } label: {
                        Label("Add item", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Line items").font(.system(size: 16))
                } footer: {
                    Text("Each item mirrors 1:1 into the grocery list.")
                        .font(.system(size: 13))
                }

                Section {
                    field("Subtotal", $subtotal)
                    field("Tax", $tax)
                    field("Total", $total)
                } header: {
                    Text("Totals").font(.system(size: 16))
                }

                Section {
                    field("Payment type", $paymentType)
                    field("Card last 4", $cardLast4)
                } header: {
                    Text("Payment").font(.system(size: 16))
                }

                Section {
                    TextEditor(text: $notes)
                        .font(.system(size: 18))
                        .frame(minHeight: 60)
                } header: {
                    Text("Notes").font(.system(size: 16))
                }

                Section {
                    if !attachedImages.isEmpty { imageArea }
                    fillFromImageButton
                    captureButtons
                } header: {
                    Text("Receipt photo").font(.system(size: 16))
                } footer: {
                    Text("\"Fill from image\" scans the receipt and fills the store and notes.")
                        .font(.system(size: 13))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 700)
            #endif
            .navigationTitle("New Receipt")
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
                        .disabled(store.isEmpty)
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
        TextField(label, text: text).font(.system(size: 18))
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
                .frame(width: 96, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #else
        if let ns = NSImage(data: attachedImages[index]) {
            Image(nsImage: ns).resizable().scaledToFill()
                .frame(width: 96, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
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
            if store.isEmpty, let suggested = card.suggestedTitle { store = suggested }
            if notes.isEmpty { notes = card.fullText }
        }
    }

    // MARK: - Save

    private func save() {
        let item = VaultItem(title: store.isEmpty ? "Receipt" : store,
                             notes: notes,
                             folder: folder)
        item.isReceipt = true
        item.receiptAddress = address
        item.receiptPhone = phone
        item.receiptDate = date
        item.receiptItems = lineItems.filter { !$0.name.isEmpty || !$0.price.isEmpty }
        item.receiptSubtotal = subtotal
        item.receiptTax = tax
        item.receiptTotal = total
        item.receiptPaymentType = paymentType
        item.receiptCardLast4 = cardLast4
        item.imageData = attachedImages
        modelContext.insert(item)
        dismiss()
    }
}
