//
//  AddItemView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct AddItemView: View {
    let folder: Folder
    @Binding var initialImages: [Data]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var pin = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []
    @State private var hasLoadedInitial = false
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showScannerMac = false
    @State private var showPlaceCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var viewingImage: ViewableImage?
    @State private var isReadingCard = false
    @State private var isCapturingPlace = false

    private struct ViewableImage: Identifiable {
        let id = UUID()
        let data: Data
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.system(size: 18))
                } header: {
                    Text("Name").font(.system(size: 16))
                }

                Section {
                    TextField("PIN, code, or password", text: $pin)
                        .font(.system(size: 20, design: .monospaced))
                        #if os(iOS)
                        .keyboardType(folder.name == "Cards" ? .numberPad : .default)
                        #endif
                } header: {
                    Text("PIN / Code").font(.system(size: 16))
                }

                Section {
                    TextEditor(text: $notes)
                        .font(.system(size: 18))
                        .frame(minHeight: 80)
                } header: {
                    Text("Notes").font(.system(size: 16))
                }

                // Capture + large image display, in the space below Notes.
                Section {
                    captureButtons
                    if !attachedImages.isEmpty {
                        fillFromImageButton
                    }
                    imageArea
                } header: {
                    Text(folder.name == "Cards" ? "Card Image" : "Image")
                        .font(.system(size: 16))
                } footer: {
                    if !attachedImages.isEmpty {
                        Text("\"Fill from image\" reads the card with on-device text recognition and fills any empty fields — you can edit them before saving.")
                            .font(.system(size: 13))
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 640)
            #endif
            .navigationTitle("New Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .onAppear {
                if !hasLoadedInitial {
                    attachedImages = initialImages
                    hasLoadedInitial = true
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
            .sheet(isPresented: $showScanner) {
                DocumentScannerView { pages in
                    attachedImages.append(contentsOf: pages)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { data in
                    attachedImages.append(data)
                }
            }
            .sheet(isPresented: $showPlaceCamera) {
                CameraCaptureView { data in
                    Task { await runPlaceCapture(photo: data) }
                }
            }
            .sheet(item: $viewingImage) { viewable in
                ImageViewerView(imageData: viewable.data)
            }
            #else
            .sheet(isPresented: $showScannerMac) {
                ScannerSheet { pages in
                    attachedImages.append(contentsOf: pages)
                }
            }
            #endif
        }
    }

    // MARK: - Capture buttons

    private var captureButtons: some View {
        HStack(spacing: 28) {
            #if os(iOS)
            captureButton("Scan", systemImage: "doc.viewfinder") { showScanner = true }
            captureButton("Camera", systemImage: "camera") { showCamera = true }
            placeButton
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
        Button(action: action) { captureLabel(title, systemImage: systemImage) }
            .buttonStyle(.plain)
    }

    #if os(iOS)
    /// One-tap "capture a place": photograph a storefront/sign, then fill the
    /// fields from the sign's text AND drop in a GPS map of where you're standing.
    private var placeButton: some View {
        Button {
            showPlaceCamera = true
        } label: {
            VStack(spacing: 4) {
                if isCapturingPlace {
                    ProgressView().frame(height: 24)
                } else {
                    Image(systemName: "storefront").font(.system(size: 24))
                }
                Text(isCapturingPlace ? "Reading…" : "Place").font(.system(size: 14))
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isCapturingPlace)
    }
    #endif

    private func captureLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 24))
            Text(title).font(.system(size: 14))
        }
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Large image area (below Notes)

    @ViewBuilder
    private var imageArea: some View {
        if attachedImages.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(folder.name == "Cards"
                     ? "Scan or photograph the card — it'll appear here."
                     : "Add an image — it'll appear here.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(.vertical, 12)
        } else {
            VStack(spacing: 12) {
                ForEach(attachedImages.indices, id: \.self) { index in
                    largeImage(at: index)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func largeImage(at index: Int) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: attachedImages[index]) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { viewingImage = ViewableImage(data: attachedImages[index]) }
                .contextMenu { removeButton(at: index) }
        }
        #else
        if let nsImage = NSImage(data: attachedImages[index]) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contextMenu { removeButton(at: index) }
        }
        #endif
    }

    private func removeButton(at index: Int) -> some View {
        Button(role: .destructive) {
            attachedImages.remove(at: index)
        } label: {
            Label("Remove Image", systemImage: "trash")
        }
    }

    // MARK: - Fill from image (on-device OCR)

    private var fillFromImageButton: some View {
        Button {
            fillFromCard()
        } label: {
            HStack(spacing: 8) {
                if isReadingCard {
                    ProgressView()
                } else {
                    Image(systemName: "text.viewfinder").font(.system(size: 18))
                }
                Text(isReadingCard ? "Reading…" : "Fill from image")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .disabled(isReadingCard)
    }

    /// Read the first image with on-device OCR and fill any EMPTY fields — never
    /// overwrites something the user already typed.
    private func fillFromCard() {
        guard let first = attachedImages.first else { return }
        Task {
            isReadingCard = true
            defer { isReadingCard = false }
            guard let card = await CardTextRecognizer.recognize(from: first) else { return }

            // On an Apple-Intelligence device, let the on-device model sort the
            // text into the right fields; otherwise use the plain OCR heuristics.
            if let smart = await CardFieldExtractor.extract(from: card.fullText) {
                if title.isEmpty, !smart.title.isEmpty { title = smart.title }
                if pin.isEmpty, !smart.number.isEmpty { pin = smart.number }
                if notes.isEmpty, !smart.notes.isEmpty { notes = smart.notes }
            } else {
                if title.isEmpty, let suggested = card.suggestedTitle { title = suggested }
                if pin.isEmpty, let number = card.suggestedNumber { pin = number }
            }
            // Whatever ran, never leave notes blank when text was read.
            if notes.isEmpty { notes = card.fullText }
        }
    }

    // MARK: - Capture Place (one tap: sign photo -> fields + GPS map)

    #if os(iOS)
    /// One-tap place capture. The photographed storefront/sign becomes the header
    /// image, its text fills any empty fields (name -> title, hours/phone/address
    /// -> notes), and a GPS map of the current location is appended. Everything
    /// stays editable before Save.
    private func runPlaceCapture(photo: Data) async {
        isCapturingPlace = true
        defer { isCapturingPlace = false }

        // The sign photo leads (becomes the header image).
        attachedImages.insert(photo, at: 0)

        // Read the sign and fill empty fields — on-device model if available,
        // else the plain OCR heuristics.
        if let card = await CardTextRecognizer.recognize(from: photo) {
            if let smart = await CardFieldExtractor.extract(from: card.fullText) {
                if title.isEmpty, !smart.title.isEmpty { title = smart.title }
                if pin.isEmpty, !smart.number.isEmpty { pin = smart.number }
                if notes.isEmpty, !smart.notes.isEmpty { notes = smart.notes }
            } else {
                if title.isEmpty, let suggested = card.suggestedTitle { title = suggested }
            }
            if notes.isEmpty { notes = card.fullText }
        }

        // Drop in a GPS-embedded map of where you're standing.
        if let map = await LocationMapCapture.captureCurrentLocationMap() {
            attachedImages.append(map)
        }
    }
    #endif

    // MARK: - Save

    private func save() {
        let newItem = VaultItem(
            title: title.isEmpty ? "Untitled" : title,
            notes: notes,
            pin: pin,
            folder: folder
        )
        newItem.imageData = attachedImages
        modelContext.insert(newItem)
        dismiss()
    }
}

// Lets `Data` drive `.sheet(item:)` — used by ItemDetailView's image viewer.
extension Data: @retroactive Identifiable {
    public var id: Int { hashValue }
}
