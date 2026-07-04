//
//  ItemListView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct ItemListView: View {
    let folder: Folder
    @Binding var selectedItem: VaultItem?
    @Binding var searchText: String
    @Environment(\.modelContext) private var modelContext
    @State private var showAddItem = false
    @State private var showAddContact = false
    @State private var showAddCard = false
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var scannedPages: [Data] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    #if os(macOS)
    @State private var showScannerSheet = false
    #endif

    var filteredItems: [VaultItem] {
        let items = (folder.items ?? []).sorted { $0.dateModified > $1.dateModified }
        if searchText.isEmpty {
            return items
        }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Dispatch by the folder's TEMPLATE, not its name (roadmap 001/002).
    var isContactFolder: Bool { folder.template == .contacts }

    var body: some View {
        List(selection: $selectedItem) {
            ForEach(filteredItems) { item in
                itemRow(item)
                    .tag(item)
            }
            .onDelete(perform: deleteItems)
        }
        .resizingNavigationTitle(folder.name)
        #if os(macOS)
        // Continuity Camera import removed (CloudKit sync makes the iPhone-camera
        // path redundant on the Mac). USB/network scanning via ScannerSheet stays.
        .sheet(isPresented: $showScannerSheet) {
            ScannerSheet { pages in
                scannedPages = pages
                showAddItem = true
            }
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addTapped() } label: { Label("Add Item", systemImage: "plus") }
            }
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button { showScannerSheet = true } label: { Label("Scan", systemImage: "scanner") }
            }
            #endif
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddItem) {
            AddItemView(folder: folder, initialImages: $scannedPages)
                .onDisappear {
                    scannedPages = []
                }
        }
        #else
        .sheet(isPresented: $showAddItem) {
            AddItemView(folder: folder, initialImages: $scannedPages)
                .onDisappear {
                    scannedPages = []
                }
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddContact) {
            ContactEditView(folder: folder)
        }
        #else
        .sheet(isPresented: $showAddContact) {
            ContactEditView(folder: folder)
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddCard) {
            CardEditView(folder: folder)
        }
        #else
        .sheet(isPresented: $showAddCard) {
            CardEditView(folder: folder)
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showScanner, onDismiss: {
            if !scannedPages.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showAddItem = true
                }
            }
        }) {
            DocumentScannerView { pages in
                scannedPages = pages
            }
        }
        #endif
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, matching: .images)
        .onChange(of: selectedPhotos) { _, newPhotos in
            Task {
                var images: [Data] = []
                for photo in newPhotos {
                    if let data = try? await photo.loadTransferable(type: Data.self) {
                        images.append(data)
                    }
                }
                if !images.isEmpty {
                    scannedPages = images
                    selectedPhotos = []
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAddItem = true
                    }
                }
            }
        }
        .dropDestination(for: String.self) { droppedStrings, _ in
            for text in droppedStrings {
                let newItem = VaultItem(title: text, folder: folder)
                modelContext.insert(newItem)
            }
            return true
        }
    }

    private func addTapped() {
        // Route the "+" by folder template. Only Contacts has a specialized
        // create sheet so far; every other template still opens the generic
        // AddItemView (with Scan/Camera/Library on it) until its own sheet is
        // built. Photos never reaches here — ContentView routes it to the media
        // library — but it's handled for completeness.
        switch folder.template {
        case .contacts: showAddContact = true
        case .cards:    showAddCard = true
        case .photos:   showPhotoPicker = true
        default:        showAddItem = true
        }
    }

    @ViewBuilder
    private func itemRow(_ item: VaultItem) -> some View {
        HStack(spacing: 12) {
            // Show first image thumbnail if available
            #if canImport(UIKit)
            if let firstImage = item.imageData.first,
               let uiImage = UIImage(data: firstImage) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            #endif

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))

                HStack(spacing: 8) {
                    if !item.imageData.isEmpty {
                        Label("\(item.imageData.count)", systemImage: "doc.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.dateModified, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .draggable(item.title) {
            Label(item.title, systemImage: "doc.fill")
                .padding(8)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let items = filteredItems
        for index in offsets {
            modelContext.delete(items[index])
        }
    }
}
