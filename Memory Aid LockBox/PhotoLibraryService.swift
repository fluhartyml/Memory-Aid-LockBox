//
//  PhotoLibraryService.swift
//  Memory Aid LockBox
//
//  Moves media OUT of Apple Photos and into the vault, and exports media back.
//
//  "Move" safety rule: the vault copy is written and verified (saved to the
//  store) BEFORE any original is deleted from Apple Photos. If the save fails,
//  nothing is deleted. iOS shows its own system "Delete items?" confirmation
//  for the removal — that prompt is required by Apple and cannot be skipped.
//

import Foundation
import SwiftUI
import Photos
import PhotosUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Picked video → file URL

/// PhotosPicker hands videos to us as a file; this copies it somewhere we can
/// read so we never have to hold a whole movie in memory just to identify it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

// MARK: - Import (move into the vault)

struct MediaImportSummary {
    var imported = 0
    var failures = 0
    /// Apple Photos local identifiers of items that were saved into the vault
    /// and are therefore safe to delete from Photos (the "move").
    var identifiersToRemove: [String] = []
}

@MainActor
struct MediaImporter {
    let modelContext: ModelContext
    let folder: Folder

    func importItems(_ items: [PhotosPickerItem]) async -> MediaImportSummary {
        var summary = MediaImportSummary()

        for item in items {
            if let asset = await makeAsset(from: item) {
                modelContext.insert(asset)
                summary.imported += 1
                if let identifier = item.itemIdentifier {
                    summary.identifiersToRemove.append(identifier)
                }
            } else {
                summary.failures += 1
            }
        }

        // Verify-before-delete: persist the vault copies first. If this throws,
        // we drop all delete identifiers so nothing leaves Apple Photos.
        do {
            try modelContext.save()
        } catch {
            summary.identifiersToRemove = []
        }
        return summary
    }

    private func makeAsset(from item: PhotosPickerItem) async -> MediaAsset? {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            return await makeVideoAsset(from: item)
        } else {
            return await makePhotoAsset(from: item)
        }
    }

    private func makePhotoAsset(from item: PhotosPickerItem) async -> MediaAsset? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let thumb = MediaThumbnailer.photoThumbnail(from: data)
        return MediaAsset(type: .photo, data: data, thumbnailData: thumb, folder: folder)
    }

    private func makeVideoAsset(from item: PhotosPickerItem) async -> MediaAsset? {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        guard let data = try? Data(contentsOf: movie.url) else { return nil }
        let thumb = await MediaThumbnailer.videoThumbnail(fileURL: movie.url)
        let duration = await MediaThumbnailer.videoDuration(fileURL: movie.url)
        return MediaAsset(type: .video,
                          data: data,
                          thumbnailData: thumb,
                          originalFileName: movie.url.lastPathComponent,
                          durationSeconds: duration,
                          folder: folder)
    }
}

// MARK: - Photos library access + delete + export

@MainActor
enum PhotoLibraryService {

    /// Full read/write access — required to delete originals on "move".
    static func requestFullAccess() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status
    }

    static func isAuthorized(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    /// Deletes the given originals from Apple Photos (the "move"). iOS presents
    /// its own confirmation; returns true only if the user confirmed and it
    /// succeeded. On cancel/error the originals stay (item becomes a copy).
    static func deleteFromPhotos(identifiers: [String]) async -> Bool {
        guard !identifiers.isEmpty else { return true }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            return false
        }
    }

    struct ExportSummary { var success = 0; var failed = 0 }

    /// Writes vault media back into Apple Photos (single or batch).
    static func exportToPhotos(_ assets: [MediaAsset]) async -> ExportSummary {
        var summary = ExportSummary()
        let status = await requestFullAccess()
        guard isAuthorized(status) else {
            summary.failed = assets.count
            return summary
        }

        for asset in assets {
            guard let data = asset.data else { summary.failed += 1; continue }

            var tempURL: URL?
            if asset.mediaType == .video {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                do { try data.write(to: url); tempURL = url }
                catch { summary.failed += 1; continue }
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    if asset.mediaType == .video, let tempURL {
                        request.addResource(with: .video, fileURL: tempURL, options: nil)
                    } else {
                        request.addResource(with: .photo, data: data, options: nil)
                    }
                }
                summary.success += 1
            } catch {
                summary.failed += 1
            }

            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
        return summary
    }
}
