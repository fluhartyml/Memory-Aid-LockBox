//
//  CardEditView.swift
//  Memory Aid LockBox
//
//  The specialized create sheet for the Cards folder (roadmap 006). One sheet
//  serves credit/debit/loyalty/insurance/ID cards via a Type picker. Sensitive
//  values show in plain text (roadmap 003 — the vault is the mask). "Fill from
//  image" scans the card and fills empty fields (roadmap 004). Photos hold the
//  front then back of the card; presenting to a cashier is a brightened photo
//  (roadmap 006a), handled in the detail view.
//

import SwiftUI
import SwiftData
import PhotosUI

enum CardType: String, CaseIterable, Identifiable {
    case credit, debit, loyalty, insurance, id
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .credit:    return "Credit"
        case .debit:     return "Debit"
        case .loyalty:   return "Loyalty"
        case .insurance: return "Insurance"
        case .id:        return "ID"
        }
    }
}

struct CardEditView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: CardType = .credit
    @State private var number = ""
    @State private var expiry = ""
    @State private var cvv = ""
    @State private var pin = ""
    @State private var issuer = ""
    @State private var barcode = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []

    @State private var libraryItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var pendingFillAfterScan = false
    @State private var activeSheet: CardSheet?
    #if os(macOS)
    @State private var showScannerMac = false
    #endif

    private enum CardSheet: Int, Identifiable {
        case scanner, camera
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Card name", text: $name).font(.system(size: 18))
                    // Group the label with its value at the leading edge; the default
                    // Picker row spreads them to opposite edges, which reads as broken
                    // on a wide iPad row.
                    HStack(spacing: 12) {
                        Text("Type")
                        Picker("Type", selection: $type) {
                            ForEach(CardType.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        Spacer()
                    }
                    .font(.system(size: 18))
                } header: {
                    Text("Card").font(.system(size: 16))
                }

                Section {
                    field("Card number", $number)
                    field("Expiry (MM/YY)", $expiry)
                    field("CVV", $cvv)
                    field("PIN", $pin)
                    field("Issuer / bank", $issuer)
                    field("Barcode / QR", $barcode)
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
                    if !attachedImages.isEmpty { imageArea }
                    fillFromImageButton
                    captureButtons
                } header: {
                    Text("Front / Back Photo").font(.system(size: 16))
                } footer: {
                    Text("\"Fill from image\" scans the card and fills any empty fields with on-device text recognition.")
                        .font(.system(size: 13))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 640)
            #endif
            .navigationTitle("New Card")
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
                        .disabled(name.isEmpty && number.isEmpty)
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
                        Text(index == 0 ? "Front" : (index == 1 ? "Back" : "Photo \(index + 1)"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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
            if name.isEmpty, let suggested = card.suggestedTitle { name = suggested }
            if number.isEmpty, let n = Self.firstCardNumber(in: text) { number = n }
            if expiry.isEmpty, let e = Self.firstExpiry(in: text) { expiry = e }
            if notes.isEmpty { notes = text }
        }
    }

    /// First line whose digit count reads like a card number (12–19 digits).
    static func firstCardNumber(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let digitCount = line.filter(\.isNumber).count
            if (12...19).contains(digitCount) {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// First MM/YY or MM/YYYY in the text.
    static func firstExpiry(in text: String) -> String? {
        guard let range = text.range(of: "(0[1-9]|1[0-2])/(\\d{4}|\\d{2})", options: .regularExpression)
        else { return nil }
        return String(text[range])
    }

    // MARK: - Save

    private func save() {
        let item = VaultItem(title: name.isEmpty ? "Untitled Card" : name,
                             notes: notes,
                             pin: pin,
                             folder: folder)
        item.isCard = true
        item.cardNumber = number
        item.cardExpiry = expiry
        item.cardCVV = cvv
        item.cardIssuer = issuer
        item.cardTypeRaw = type.rawValue
        item.cardBarcode = barcode
        item.imageData = attachedImages
        modelContext.insert(item)
        dismiss()
    }
}
