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
    @State private var libraryItem: PhotosPickerItem?
    @State private var viewingImage: ViewableImage?

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
                    imageArea
                } header: {
                    Text(folder.name == "Cards" ? "Card Image" : "Image")
                        .font(.system(size: 16))
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
