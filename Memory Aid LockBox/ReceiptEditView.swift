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

    @State private var viewingImage: Data?
    @State private var libraryItem: PhotosPickerItem?
    @State private var fillLibraryItem: PhotosPickerItem?
    @State private var showFillLibrary = false
    @State private var isReading = false
    @State private var fillStatus: String?
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
                    if !attachedImages.isEmpty { imageArea }
                    fillFromImageButton
                } header: {
                    Text("Receipt photo").font(.system(size: 16))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\"Fill from scan\" reads the receipt and fills the address, line items, and totals. Add the store name yourself — it's usually a logo.")
                            .font(.system(size: 13))
                        if let fillStatus {
                            Text(fillStatus).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
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
                    labeledField("Subtotal", $subtotal)
                    labeledField("Tax", $tax)
                    labeledField("Total", $total)
                } header: {
                    Text("Totals").font(.system(size: 16))
                }

                Section {
                    labeledField("Payment type", $paymentType)
                    labeledField("Card last 4", $cardLast4)
                } header: {
                    Text("Payment").font(.system(size: 16))
                }

                Section {
                    // Monospaced so a preserved receipt layout keeps its columns.
                    TextEditor(text: $notes)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 60)
                } header: {
                    Text("Notes").font(.system(size: 16))
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
                        .disabled(isBlank)
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
            #if os(iOS)
            .sheet(item: $viewingImage) { data in ImageViewerView(imageData: data) }
            #endif
            .photosPicker(isPresented: $showFillLibrary, selection: $fillLibraryItem, matching: .images)
            .onChange(of: fillLibraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        attachedImages.append(data)
                        fillFromImage(from: data)
                    }
                    fillLibraryItem = nil
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        TextField(label, text: text).font(.system(size: 18))
    }

    /// A row whose label stays visible even once the value is filled (totals /
    /// payment read as bare numbers otherwise).
    private func labeledField(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.system(size: 17)).foregroundStyle(.secondary)
            Spacer()
            TextField("", text: text)
                .font(.system(size: 17))
                .multilineTextAlignment(.trailing)
        }
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
                .onTapGesture { viewingImage = attachedImages[index] }   // tap to read it zoomed
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
        Menu {
            Button { pendingFillAfterScan = true; openScanner() } label: {
                Label("Scan receipt", systemImage: "doc.viewfinder")
            }
            Button { showFillLibrary = true } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            HStack(spacing: 8) {
                if isReading { ProgressView() }
                else { Image(systemName: "text.viewfinder").font(.system(size: 18)) }
                Text(isReading ? "Reading…" : "Fill from scan").font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(isReading)
    }

    private func openScanner() {
        #if os(iOS)
        activeSheet = .scanner
        #else
        showScannerMac = true
        #endif
    }

    // MARK: - Fill from image

    private func fillFromImage(from image: Data? = nil) {
        guard let first = image ?? attachedImages.first else { return }
        Task {
            isReading = true
            defer { isReading = false }

            // 1) Deterministic geometric parse — item codes paired with the
            //    right-hand price column. The reliable path for retail receipts.
            if let scan = await CardTextRecognizer.receiptScan(from: first), !scan.items.isEmpty {
                applyScan(scan)
                let n = scan.items.count
                fillStatus = "Read \(n) item\(n == 1 ? "" : "s")\(store.isEmpty ? " — add the store name (it's usually a logo)." : ".")"
                return
            }

            // 2) Fallbacks (non-coded / messy receipts) need the OCR text.
            guard let rows = await CardTextRecognizer.receiptRows(from: first), !rows.isEmpty else {
                fillStatus = "Couldn't read any text. A Scan usually reads cleaner than a photo."
                return
            }
            let ocrText = rows.joined(separator: "\n")

            // Address + phone are printed as text — heuristic backstop either way.
            let heur = ReceiptTextParser.parse(rows)
            if address.isEmpty, let a = heur.address { address = a }
            if phone.isEmpty, let p = heur.phone { phone = p }

            // Prefer the on-device model — it re-associates prices orphaned by
            // Vision's column-by-column read. Falls back to the positional
            // heuristic when Apple Intelligence isn't available.
            if let ai = await ReceiptLLMParser.parse(ocrText: ocrText), !ai.items.isEmpty {
                let existing = lineItems.filter { !$0.name.isEmpty || !$0.price.isEmpty }
                lineItems = existing + ai.items.map { ReceiptLineItem(name: $0.name, price: $0.price) }
                if store.isEmpty, !ai.store.isEmpty { store = ai.store }
                if address.isEmpty, !ai.address.isEmpty { address = ai.address }
                if phone.isEmpty, !ai.phone.isEmpty { phone = ai.phone }
                if subtotal.isEmpty, !ai.subtotal.isEmpty { subtotal = ai.subtotal }
                if tax.isEmpty, !ai.tax.isEmpty { tax = ai.tax }
                if total.isEmpty, !ai.total.isEmpty { total = ai.total }
                let n = ai.items.count
                fillStatus = "Read \(n) item\(n == 1 ? "" : "s") with on-device AI\(store.isEmpty ? " — add the store name." : ".")"
                return
            }

            if !heur.items.isEmpty {
                let existing = lineItems.filter { !$0.name.isEmpty || !$0.price.isEmpty }
                lineItems = existing + heur.items
                if subtotal.isEmpty, let s = heur.subtotal { subtotal = s }
                if tax.isEmpty, let t = heur.tax { tax = t }
                if total.isEmpty, let t = heur.total { total = t }
                let n = heur.items.count
                fillStatus = "Read \(n) item\(n == 1 ? "" : "s")\(store.isEmpty ? " — add the store name (it's usually a logo)." : ".")"
            } else {
                // Couldn't structure it — preserve the receipt's physical layout
                // (columns aligned) as monospaced text in Notes so nothing is lost.
                if notes.isEmpty {
                    notes = await CardTextRecognizer.receiptLayoutText(from: first) ?? ocrText
                }
                fillStatus = "Couldn't structure this receipt — saved its layout as text in Notes. Edit any line."
            }
        }
    }

    // MARK: - Save

    /// A receipt is only un-savable when it's completely empty — store name is
    /// optional (it's often just a logo), so items/totals/photo are enough.
    private var isBlank: Bool {
        store.isEmpty
        && lineItems.allSatisfy { $0.name.isEmpty && $0.price.isEmpty }
        && attachedImages.isEmpty
        && subtotal.isEmpty && tax.isEmpty && total.isEmpty
    }

    private func applyScan(_ s: ReceiptTextParser.ReceiptScan) {
        let existing = lineItems.filter { !$0.name.isEmpty || !$0.price.isEmpty }
        lineItems = existing + s.items
        if address.isEmpty, !s.address.isEmpty { address = s.address }
        if phone.isEmpty, !s.phone.isEmpty { phone = s.phone }
        if subtotal.isEmpty, !s.subtotal.isEmpty { subtotal = s.subtotal }
        if tax.isEmpty, !s.tax.isEmpty { tax = s.tax }
        if total.isEmpty, !s.total.isEmpty { total = s.total }
        if paymentType.isEmpty, !s.paymentType.isEmpty { paymentType = s.paymentType }
        if cardLast4.isEmpty, !s.cardLast4.isEmpty { cardLast4 = s.cardLast4 }
    }

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
