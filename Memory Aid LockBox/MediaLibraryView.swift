//
//  MediaLibraryView.swift
//  Memory Aid LockBox
//
//  The Photos folder, reimagined as a media library that lives INSIDE the
//  vault: photos and videos are moved in from Apple Photos, viewed/played
//  here, and can be exported back out — one, several, or all.
//

import SwiftUI
import SwiftData
import Photos
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct MediaLibraryView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var isImporting = false
    @State private var isExporting = false

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []

    @State private var viewerAsset: MediaAsset?
    @State private var showDeleteConfirm = false

    // After a successful export, ask whether to keep the vault copies or move
    // them out (delete from the vault). Only the verified-exported assets.
    @State private var exportedPendingRemoval: [MediaAsset] = []
    @State private var showExportMovePrompt = false
    @State private var lastExportFailed = 0

    @State private var statusMessage: String?
    @State private var showStatus = false

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 4)]

    private var assets: [MediaAsset] {
        (folder.mediaAssets ?? []).sorted { $0.dateImported > $1.dateImported }
    }

    private var selectedAssets: [MediaAsset] {
        assets.filter { selection.contains($0.id) }
    }

    var body: some View {
        content
            .navigationTitle(folder.name)
            .toolbar { toolbarContent }
            // `photoLibrary: .shared()` is REQUIRED for itemIdentifier to be
            // populated — without it the picker runs out-of-process, identifiers
            // come back nil, and the "move" can't delete the originals.
            .photosPicker(isPresented: $showPicker,
                          selection: $pickerItems,
                          matching: .any(of: [.images, .videos]),
                          photoLibrary: .shared())
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await runImport(items) }
            }
            .overlay { if isImporting || isExporting { busyOverlay } }
            .confirmationDialog("Remove \(selection.count) item\(selection.count == 1 ? "" : "s") from the vault?",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove from Vault", role: .destructive) { deleteSelected() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes them from the lockbox only. It does not touch Apple Photos.")
            }
            .confirmationDialog("Exported \(exportedPendingRemoval.count) to Apple Photos. Remove them from the vault?",
                                isPresented: $showExportMovePrompt, titleVisibility: .visible) {
                Button("Remove from Vault", role: .destructive) {
                    for asset in exportedPendingRemoval { modelContext.delete(asset) }
                    exportedPendingRemoval = []
                    lastExportFailed = 0
                    endSelecting()
                }
                Button("Keep in Vault", role: .cancel) {
                    exportedPendingRemoval = []
                    lastExportFailed = 0
                    endSelecting()
                }
            } message: {
                Text(exportMovePromptMessage)
            }
            .alert("Memory Aid LockBox", isPresented: $showStatus) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
            #if os(iOS)
            .fullScreenCover(item: $viewerAsset) { MediaViewerView(asset: $0) }
            #else
            .sheet(item: $viewerAsset) { MediaViewerView(asset: $0).frame(minWidth: 600, minHeight: 600) }
            #endif
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if assets.isEmpty && !isImporting {
            ContentUnavailableView {
                Label("No Media Yet", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Move photos and videos in from Apple Photos. They'll live here in the vault.")
            } actions: {
                Button { importTapped() } label: {
                    Label("Import from Photos", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets) { asset in
                        tile(asset)
                    }
                }
                .padding(4)
            }
        }
    }

    private func tile(_ asset: MediaAsset) -> some View {
        let isSelected = selection.contains(asset.id)
        return MediaThumbnailImage(data: asset.thumbnailData ?? asset.data)
            .aspectRatio(1, contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: 110)
            .clipped()
            .overlay(alignment: .bottomLeading) { videoBadge(asset) }
            .overlay(alignment: .topTrailing) { if isSelecting { selectionMark(isSelected) } }
            .overlay {
                if isSelecting && isSelected {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .contentShape(Rectangle())
            .onTapGesture { tapped(asset) }
            .contextMenu { tileMenu(asset) }
    }

    @ViewBuilder
    private func videoBadge(_ asset: MediaAsset) -> some View {
        if asset.mediaType == .video {
            HStack(spacing: 3) {
                Image(systemName: "play.fill").font(.system(size: 10))
                Text(durationLabel(asset.durationSeconds)).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(4)
        }
    }

    private func selectionMark(_ isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(isSelected ? Color.accentColor : .white)
            .background(Circle().fill(.black.opacity(0.3)))
            .padding(4)
    }

    @ViewBuilder
    private func tileMenu(_ asset: MediaAsset) -> some View {
        Button { Task { await exportAssets([asset]) } } label: {
            Label("Export to Photos", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) {
            modelContext.delete(asset)
        } label: {
            Label("Remove from Vault", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isSelecting {
                Button { Task { await exportAssets(selectedAssets) } } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)

                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(selection.isEmpty)

                Button("Done") { isSelecting = false; selection.removeAll() }
            } else {
                Button { importTapped() } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                Button("Select") { isSelecting = true }
                    .disabled(assets.isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func tapped(_ asset: MediaAsset) {
        if isSelecting {
            if selection.contains(asset.id) { selection.remove(asset.id) }
            else { selection.insert(asset.id) }
        } else {
            viewerAsset = asset
        }
    }

    private func importTapped() {
        Task {
            let status = await PhotoLibraryService.requestFullAccess()
            if PhotoLibraryService.isAuthorized(status) {
                showPicker = true
            } else {
                statusMessage = "Photos access is needed to move photos and videos into the vault. Enable it in Settings → Memory Aid LockBox → Photos."
                showStatus = true
            }
        }
    }

    private func runImport(_ items: [PhotosPickerItem]) async {
        isImporting = true
        let importer = MediaImporter(modelContext: modelContext, folder: folder)
        let summary = await importer.importItems(items)

        var moved = false
        if !summary.identifiersToRemove.isEmpty {
            moved = await PhotoLibraryService.deleteFromPhotos(identifiers: summary.identifiersToRemove)
        }

        pickerItems = []
        isImporting = false

        var parts: [String] = []
        if summary.imported > 0 {
            parts.append("\(summary.imported) item\(summary.imported == 1 ? "" : "s") imported into the vault.")
            parts.append(moved
                ? "Originals were removed from Apple Photos."
                : "Originals are still in Apple Photos (removal was canceled or unavailable) — they're copies for now.")
        }
        if summary.failures > 0 {
            parts.append("\(summary.failures) couldn't be read and were skipped.")
        }
        if !parts.isEmpty {
            statusMessage = parts.joined(separator: "\n\n")
            showStatus = true
        }
    }

    private func exportAssets(_ targets: [MediaAsset]) async {
        guard !targets.isEmpty else { return }
        isExporting = true
        let summary = await PhotoLibraryService.exportToPhotos(targets)
        isExporting = false

        if summary.successCount > 0 {
            // Offer keep-or-move for the items that actually exported.
            exportedPendingRemoval = summary.succeeded
            lastExportFailed = summary.failed
            showExportMovePrompt = true
        } else {
            statusMessage = "Export failed for \(summary.failed) item\(summary.failed == 1 ? "" : "s")."
            showStatus = true
            endSelecting()
        }
    }

    private func deleteSelected() {
        for asset in selectedAssets {
            modelContext.delete(asset)
        }
        endSelecting()
    }

    private func endSelecting() {
        selection.removeAll()
        isSelecting = false
    }

    private var exportMovePromptMessage: String {
        var text = "They're now in Apple Photos. \"Remove\" deletes the vault copy (a move); \"Keep\" leaves a copy here."
        if lastExportFailed > 0 {
            text += "\n\n\(lastExportFailed) item\(lastExportFailed == 1 ? "" : "s") couldn't be exported and stay in the vault."
        }
        return text
    }

    private func durationLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Busy overlay

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView(isImporting ? "Importing…" : "Exporting…")
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Cross-platform thumbnail image

struct MediaThumbnailImage: View {
    let data: Data?

    var body: some View {
        #if canImport(UIKit)
        if let data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable()
        } else {
            placeholder
        }
        #else
        if let data, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage).resizable()
        } else {
            placeholder
        }
        #endif
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }
}
