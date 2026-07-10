//
//  PhotoJournalView.swift
//  Memory Aid LockBox
//
//  A curated photo album (template .photoJournal). Unlike the master Photos
//  library (a grid it OWNS), a journal owns nothing — it holds an ordered list
//  of references (Folder.journalAssetIDs) to MediaAssets owned by the master
//  Photos folder, shown as a one-column list: thumbnail + title + caption per
//  row. Tap a row to open the photo full-screen and edit its title/caption
//  (the same MediaViewerView the master library uses). Removing a row or
//  deleting the journal never deletes the photo from master.
//
//  Add flows (Take Picture / Import / Add-from-master) and the master "Add to
//  Photo Journal" push flow land in later chunks.
//

import SwiftUI
import SwiftData
import PhotosUI

struct PhotoJournalView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @Query private var allAssets: [MediaAsset]
    @Query private var folders: [Folder]

    @State private var viewerAsset: MediaAsset?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var isImporting = false
    @State private var showMasterPicker = false
    @State private var statusMessage: String?
    @State private var showStatus = false
    #if os(iOS)
    @State private var showCamera = false
    #endif

    /// The one master Photos folder — it owns the bytes; the journal only
    /// references. Capture/import here store into this folder.
    private var master: Folder? { folders.first { $0.template == .photos } }

    /// The journal's referenced photos, resolved from the master library and
    /// kept in the journal's stored order. References whose photo no longer
    /// exists in master (deleted there) are skipped gracefully.
    private var assets: [MediaAsset] {
        let byID = Dictionary(allAssets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return folder.journalAssetIDs.compactMap { byID[$0] }
    }

    var body: some View {
        content
            .resizingNavigationTitle(folder.name)
            .toolbar { toolbarContent }
            .photosPicker(isPresented: $showPicker,
                          selection: $pickerItems,
                          matching: .any(of: [.images, .videos]))
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await runImport(items) }
            }
            .overlay { if isImporting { busyOverlay } }
            .sheet(isPresented: $showMasterPicker) {
                if let master {
                    MasterPhotoPickerView(master: master,
                                          excluding: Set(folder.journalAssetIDs)) { ids in
                        addReferences(ids)
                    }
                }
            }
            .alert("Memory Aid LockBox", isPresented: $showStatus) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
            #if os(iOS)
            .fullScreenCover(item: $viewerAsset) { MediaViewerView(asset: $0) }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { data in addCapturedPhoto(data) }
            }
            #else
            .sheet(item: $viewerAsset) { MediaViewerView(asset: $0).frame(minWidth: 600, minHeight: 600) }
            #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                #if os(iOS)
                Button { showCamera = true } label: {
                    Label("Take Picture", systemImage: "camera")
                }
                #endif
                Button { showPicker = true } label: {
                    Label("Import from Camera Roll", systemImage: "photo.on.rectangle")
                }
                Button { showMasterPicker = true } label: {
                    Label("Add from Library", systemImage: "photo.stack")
                }
            } label: {
                Label("Add Photo", systemImage: "plus")
            }
            .disabled(master == nil)
        }
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("Importing…")
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var content: some View {
        if assets.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Photos Yet")
                } icon: {
                    Image(systemName: "photo.stack")
                }
            } description: {
                Text("This journal will hold a curated set of photos. Add some to get started.")
            }
        } else {
            List {
                ForEach(assets) { asset in
                    row(asset)
                        .contentShape(Rectangle())
                        .onTapGesture { viewerAsset = asset }
                        // Long-press to remove the reference only — the photo is
                        // preserved in the master vault. No confirm (long-press is
                        // the friction). See feedback_long_press_delete_over_swipe.
                        .contextMenu {
                            Button(role: .destructive) { removeReference(asset.id) } label: {
                                Label("Remove from Journal", systemImage: "minus.circle")
                            }
                        }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
    }

    private func row(_ asset: MediaAsset) -> some View {
        HStack(spacing: 12) {
            MediaThumbnailImage(data: asset.thumbnailData ?? asset.data)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.title.isEmpty ? "Untitled" : asset.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(asset.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if !asset.caption.isEmpty {
                    Text(asset.caption)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add flows (photos are owned by master, referenced here)

    /// Import from the camera roll into the master folder, then reference the new
    /// photos in this journal (copy — Apple Photos originals are left in place).
    private func runImport(_ items: [PhotosPickerItem]) async {
        guard let master else { pickerItems = []; return }
        isImporting = true
        let importer = MediaImporter(modelContext: modelContext, folder: master)
        let summary = await importer.importItems(items)
        if !summary.createdAssetIDs.isEmpty {
            var refs = folder.journalAssetIDs
            refs.append(contentsOf: summary.createdAssetIDs)
            folder.journalAssetIDs = refs
            try? modelContext.save()
        }
        pickerItems = []
        isImporting = false
        if summary.failures > 0 {
            statusMessage = "\(summary.failures) item\(summary.failures == 1 ? "" : "s") couldn't be read and were skipped."
            showStatus = true
        }
    }

    /// Remove a photo's reference from this journal. The MediaAsset stays in the
    /// master vault (and any other journals) — only this journal's link is cut.
    private func removeReference(_ id: UUID) {
        folder.journalAssetIDs = folder.journalAssetIDs.filter { $0 != id }
        try? modelContext.save()
    }

    /// Reference existing master photos into this journal (no bytes copied),
    /// skipping any already present, preserving the picker's order.
    private func addReferences(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var refs = folder.journalAssetIDs
        let existing = Set(refs)
        for id in ids where !existing.contains(id) { refs.append(id) }
        folder.journalAssetIDs = refs
        try? modelContext.save()
    }

    #if os(iOS)
    /// Store a freshly captured photo in the master folder and reference it here.
    private func addCapturedPhoto(_ data: Data) {
        guard let master else { return }
        let thumb = MediaThumbnailer.photoThumbnail(from: data)
        let asset = MediaAsset(type: .photo, data: data, thumbnailData: thumb, folder: master)
        modelContext.insert(asset)
        var refs = folder.journalAssetIDs
        refs.append(asset.id)
        folder.journalAssetIDs = refs
        try? modelContext.save()
    }
    #endif
}
