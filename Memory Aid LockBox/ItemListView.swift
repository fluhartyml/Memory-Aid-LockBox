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
    @State private var showAddCodes = false
    @State private var showAddJournal = false
    @State private var showAddAppt = false
    @State private var showAddReceipt = false
    @State private var showConfigureFields = false
    @State private var exportFile: ExportFile?

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var scannedPages: [Data] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    #if os(macOS)
    @State private var showScannerSheet = false
    #endif

    var filteredItems: [VaultItem] {
        // Journal sorts by each entry's OWN date+time (newest first) so editing
        // an old entry never bumps it; every other folder sorts by last-modified.
        let source = folder.items ?? []
        let items = folder.template == .journal
            ? source.sorted { $0.journalDate > $1.journalDate }
            : source.sorted { $0.dateModified > $1.dateModified }
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
            // Per-folder menu: Configure Fields (005a/b) for every item folder,
            // plus Journal export (roadmap 009 + Michael 7/6).
            if folder.template != .photos {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button { showConfigureFields = true } label: {
                            Label("Configure Fields", systemImage: "slider.horizontal.3")
                        }
                        if folder.template == .journal {
                            Divider()
                            Button { exportJournal(asPDF: false) } label: {
                                Label("Export Markdown (.zip)", systemImage: "doc.plaintext")
                            }
                            Button { exportJournal(asPDF: true) } label: {
                                Label("Export PDF", systemImage: "doc.richtext")
                            }
                        }
                    } label: {
                        Label("Folder options", systemImage: "ellipsis.circle")
                    }
                }
            }
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button { showScannerSheet = true } label: { Label("Scan", systemImage: "scanner") }
            }
            #endif
        }
        .sheet(isPresented: $showConfigureFields) {
            ConfigureFieldsView(folder: folder)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddItem) {
            CustomNotesEditView(folder: folder, initialImages: $scannedPages)
                .holdsVaultActivity()
                .onDisappear {
                    scannedPages = []
                }
        }
        #else
        .sheet(isPresented: $showAddItem) {
            CustomNotesEditView(folder: folder, initialImages: $scannedPages)
                .holdsVaultActivity()
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
                .holdsVaultActivity()
        }
        #else
        .sheet(isPresented: $showAddCard) {
            CardEditView(folder: folder)
                .holdsVaultActivity()
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddCodes) {
            CodesAccountsEditView(folder: folder)
                .holdsVaultActivity()
        }
        #else
        .sheet(isPresented: $showAddCodes) {
            CodesAccountsEditView(folder: folder)
                .holdsVaultActivity()
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddJournal) {
            JournalEntryEditView(folder: folder)
                .holdsVaultActivity()
        }
        #else
        .sheet(isPresented: $showAddJournal) {
            JournalEntryEditView(folder: folder)
                .holdsVaultActivity()
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddAppt) {
            AppointmentEditView(folder: folder)
                .holdsVaultActivity()
        }
        #else
        .sheet(isPresented: $showAddAppt) {
            AppointmentEditView(folder: folder)
                .holdsVaultActivity()
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showAddReceipt) {
            ReceiptEditView(folder: folder)
                .holdsVaultActivity()
        }
        #else
        .sheet(isPresented: $showAddReceipt) {
            ReceiptEditView(folder: folder)
                .holdsVaultActivity()
        }
        #endif
        #if os(iOS)
        .sheet(item: $exportFile) { file in
            FileShareSheet(urls: [file.url])
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
        // Route the "+" by folder template — each folder gets its own specialized
        // sheet, never a shared generic one. Contacts/Cards/Codes have theirs;
        // Custom/Notes uses CustomNotesEditView (the catch-all). Journal/Receipts/
        // Appointments fall through to that catch-all only until their own sheets
        // are built. Photos never reaches here (ContentView routes it to the media
        // library), handled for completeness.
        switch folder.template {
        case .contacts:      showAddContact = true
        case .cards:         showAddCard = true
        case .codesAccounts: showAddCodes = true
        case .journal:       showAddJournal = true
        case .appointments:  showAddAppt = true
        case .receipts:      showAddReceipt = true
        case .photos:        showPhotoPicker = true
        case .customNotes:   showAddItem = true
        }
    }

    // MARK: - Journal export (roadmap 009 + Michael 7/6)

    private var journalEntries: [JournalExporter.Entry] {
        filteredItems.map {
            JournalExporter.Entry(date: $0.journalDate, title: $0.title,
                                  body: $0.notes, images: $0.imageData)
        }
    }

    private func exportJournal(asPDF: Bool) {
        let url = asPDF
            ? JournalExporter.pdf(folderName: folder.name, entries: journalEntries)
            : JournalExporter.markdownArchive(folderName: folder.name, entries: journalEntries)
        guard let url else { return }
        #if os(iOS)
        exportFile = ExportFile(url: url)
        #else
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
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
                    // Journal rows read as YYYY MMM DD HH:MM:SS by the entry's own
                    // date; other folders show the last-modified day.
                    if folder.template == .journal {
                        Text(JournalExporter.label(for: item.journalDate, title: ""))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(item.dateModified, format: .dateTime.month(.abbreviated).day().year())
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
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
