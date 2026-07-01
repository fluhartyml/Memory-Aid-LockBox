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

struct ItemDetailView: View {
    @Bindable var item: VaultItem
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showShareSheet = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var viewingImage: Data?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header / hero image: the first attachment, shown as a banner
                // across the top of the note. "Set as Header" on any other photo
                // moves it here.
                if let heroData = item.imageData.first {
                    heroImage(heroData)
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
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task {
                if let data = try? await newPhoto?.loadTransferable(type: Data.self) {
                    item.imageData.append(data)
                    item.dateModified = Date()
                }
            }
        }
        .onChange(of: item.title) { _, _ in item.dateModified = Date() }
        .onChange(of: item.notes) { _, _ in item.dateModified = Date() }
        .onChange(of: item.pin) { _, _ in item.dateModified = Date() }
        #if os(iOS)
        .sheet(item: $viewingImage) { imageData in
            ImageViewerView(imageData: imageData)
        }
        #endif
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

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 30) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 24))
                        Text("Library")
                            .font(.system(size: 14))
                    }
                }

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
    private func heroImage(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { viewingImage = data }
                .contextMenu { heroMenu(for: data) }
        }
        #else
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contextMenu { heroMenu(for: data) }
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
        Button(role: .destructive) {
            if !item.imageData.isEmpty {
                item.imageData.removeFirst()
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
