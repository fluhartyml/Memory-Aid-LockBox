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
    @State private var cvv = ""        // back code (Visa/MC/Discover, 3 digits)
    @State private var cvvFront = ""   // front code (Amex CID, 4 digits)
    @State private var pin = ""
    @State private var issuer = ""
    @State private var barcode = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []
    @State private var fullScreenImage: Data?

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
                    if !attachedImages.isEmpty { imageArea }
                    scanCardButton
                    addPhotoButtons
                } header: {
                    Text("Card Photos").font(.system(size: 16))
                } footer: {
                    Text("Scan Card reads both sides on-device and fills the number, expiry, and security codes for you. Or add a photo manually. Verify the fields — small or embossed print scans imperfectly.")
                        .font(.system(size: 13))
                }

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
                    field("CVN — back (3 digits)", $cvv)
                    field("CVN — front / Amex (4 digits)", $cvvFront)
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
                            fillFromImage(pages: pages)
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
                        fillFromImage(pages: pages)
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
            .fullScreenCover(item: $fullScreenImage) { data in
                ImageViewerView(imageData: data)
            }
            #else
            .sheet(item: $fullScreenImage) { data in
                fullImageSheet(data)
            }
            #endif
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        TextField(label, text: text).font(.system(size: 18))
    }

    // MARK: - Photos

    #if os(macOS)
    @ViewBuilder
    private func fullImageSheet(_ data: Data) -> some View {
        VStack {
            if let ns = NSImage(data: data) {
                Image(nsImage: ns).resizable().scaledToFit()
            }
            Button("Done") { fullScreenImage = nil }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
    }
    #endif

    private var imageArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachedImages.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        thumbnail(at: index)
                            .contentShape(Rectangle())
                            .onTapGesture { fullScreenImage = attachedImages[index] }
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
                .frame(width: 220, height: 139).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        #else
        if let ns = NSImage(data: attachedImages[index]) {
            Image(nsImage: ns).resizable().scaledToFill()
                .frame(width: 220, height: 139).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        #endif
    }

    /// Manual "add a photo" options, secondary to Scan Card. No separate "Scan"
    /// button — scanning is the primary action above and it also fills the fields.
    private var addPhotoButtons: some View {
        HStack(spacing: 28) {
            Text("or add a photo:").font(.system(size: 13)).foregroundStyle(.secondary)
            #if os(iOS)
            captureButton("Camera", "camera") { activeSheet = .camera }
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

    /// The one primary action: scan the card. It captures the photo(s) AND fills
    /// the fields from them — Scan and "Fill from image" are the same button now.
    private var scanCardButton: some View {
        Button {
            pendingFillAfterScan = true
            #if os(iOS)
            activeSheet = .scanner
            #else
            showScannerMac = true
            #endif
        } label: {
            HStack(spacing: 10) {
                if isReading { ProgressView() }
                else { Image(systemName: "doc.viewfinder").font(.system(size: 22)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isReading ? "Reading…" : "Scan Card")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Front & back — fills the fields for you")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(isReading)
    }

    // MARK: - Fill from image

    /// OCR every scanned side and fill empty fields from the pooled text. The
    /// card number and expiry can sit on either face — Amex prints the number
    /// flat on the back, Visa embosses it on the front — so we don't assume a
    /// page position for them. The two security codes are told apart by length:
    /// a 4-digit group is the Amex front CID, a 3-digit group the back CVN.
    /// Every value in the vault is sensitive by default, so the codes are read
    /// in too. (Embossed numbers are low-contrast and may scan imperfectly.)
    private func fillFromImage(pages: [Data]) {
        let sources = pages.isEmpty ? attachedImages : pages
        guard !sources.isEmpty else { return }
        Task {
            isReading = true
            defer { isReading = false }

            var recognized: [RecognizedCard] = []
            for data in sources {
                if let r = await CardTextRecognizer.recognize(from: data) { recognized.append(r) }
            }
            guard !recognized.isEmpty else { return }
            let text = recognized.map(\.fullText).joined(separator: "\n")

            if number.isEmpty, let n = Self.firstCardNumber(in: text) { number = n }
            if expiry.isEmpty, let e = Self.firstExpiry(in: text) { expiry = e }

            // Debit vs credit is often printed on the face; pick it up so the
            // auto-name is right.
            let upper = text.uppercased()
            if upper.contains("DEBIT") { type = .debit }
            else if upper.contains("CREDIT") { type = .credit }

            // Auto-name from the card's network + type (e.g. "Visa Debit") — read
            // from the number, not from marketing text on the card ("Activate this
            // card today" was landing here before).
            if name.isEmpty {
                let network = Self.cardNetwork(forDigits: number.filter(\.isNumber))
                let composed = [network, type.displayName].compactMap { $0 }.joined(separator: " ")
                if !composed.isEmpty { name = composed }
            }

            let numberDigits = number.filter(\.isNumber)
            // 15-digit Amex carries a 4-digit CID; only look for it on Amex so a
            // Visa's 4-digit number block is never mistaken for a code.
            if cvvFront.isEmpty, numberDigits.count == 15,
               let f = Self.securityCode(in: text, length: 4, notPartOf: numberDigits) {
                cvvFront = f
            }
            if cvv.isEmpty, let b = Self.securityCode(in: text, length: 3, notPartOf: numberDigits) {
                cvv = b
            }
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

    /// The card network inferred from the leading digits (Visa/Mastercard/Amex/
    /// Discover), used to auto-name the card. Returns nil if it doesn't match a
    /// known prefix.
    static func cardNetwork(forDigits d: String) -> String? {
        if d.hasPrefix("4") { return "Visa" }
        if d.hasPrefix("34") || d.hasPrefix("37") { return "Amex" }
        if d.hasPrefix("6011") || d.hasPrefix("65") { return "Discover" }
        if let two = Int(d.prefix(2)), (51...55).contains(two) { return "Mastercard" }
        if let four = Int(d.prefix(4)), (2221...2720).contains(four) { return "Mastercard" }
        return nil
    }

    /// First MM/YY or MM/YYYY in the text.
    static func firstExpiry(in text: String) -> String? {
        guard let range = text.range(of: "(0[1-9]|1[0-2])/(\\d{4}|\\d{2})", options: .regularExpression)
        else { return nil }
        return String(text[range])
    }

    /// A standalone group of exactly `length` digits — the security code (CVN /
    /// Amex CID). Skips the expiry (it carries a "/") and any group that's part
    /// of the card number, so the code isn't confused with a number block.
    static func securityCode(in text: String, length: Int, notPartOf number: String) -> String? {
        for raw in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            if raw.contains("/") { continue }                 // expiry, not a code
            let digits = raw.filter(\.isNumber)
            guard digits.count == length else { continue }
            if !number.isEmpty && number.contains(digits) { continue }  // a card-number block
            return digits
        }
        return nil
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
        item.cardCVVFront = cvvFront
        item.cardIssuer = issuer
        item.cardTypeRaw = type.rawValue
        item.cardBarcode = barcode
        item.imageData = attachedImages
        modelContext.insert(item)
        dismiss()
    }
}
