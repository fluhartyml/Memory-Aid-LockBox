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
        // Prefer the Photos framework with iCloud download enabled so a photo
        // that isn't stored locally is fetched instead of being silently
        // skipped. Fall back to the picker's own transfer if there's no
        // identifier (only the in-process `.shared()` picker provides one).
        var data: Data?
        if let identifier = item.itemIdentifier {
            data = await PhotoLibraryService.photoData(forLocalIdentifier: identifier)
        }
        if data == nil {
            data = try? await item.loadTransferable(type: Data.self)
        }
        guard let data else { return nil }
        let thumb = MediaThumbnailer.photoThumbnail(from: data)
        return MediaAsset(type: .photo, data: data, thumbnailData: thumb, folder: folder)
    }

    private func makeVideoAsset(from item: PhotosPickerItem) async -> MediaAsset? {
        // Same as photos: force an iCloud download via the Photos framework so
        // an un-downloaded video is retrieved rather than skipped.
        var fileURL: URL?
        if let identifier = item.itemIdentifier {
            fileURL = await PhotoLibraryService.videoFileURL(forLocalIdentifier: identifier)
        }
        if fileURL == nil, let movie = try? await item.loadTransferable(type: PickedMovie.self) {
            fileURL = movie.url
        }
        guard let url = fileURL else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let thumb = await MediaThumbnailer.videoThumbnail(fileURL: url)
        let duration = await MediaThumbnailer.videoDuration(fileURL: url)
        return MediaAsset(type: .video,
                          data: data,
                          thumbnailData: thumb,
                          originalFileName: url.lastPathComponent,
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

    /// Full photo bytes for a Photos asset, forcing an iCloud download so a
    /// photo that isn't stored locally is retrieved instead of failing to read.
    static func photoData(forLocalIdentifier identifier: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true   // download from iCloud if needed
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isSynchronous = false
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: data)
            }
        }
    }

    /// Writes a Photos video to a temporary file, forcing an iCloud download.
    /// Returns the file URL (caller deletes it) or nil if it couldn't be read.
    static func videoFileURL(forLocalIdentifier identifier: String) async -> URL? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .video })
                ?? resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first
        else { return nil }
        let ext = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "mov"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true   // download from iCloud if needed
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: dest, options: options) { error in
                continuation.resume(returning: error == nil ? dest : nil)
            }
        }
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

    struct ExportSummary {
        /// The assets that actually made it into Apple Photos — only these are
        /// safe to remove from the vault if the user chooses "move".
        var succeeded: [MediaAsset] = []
        var failed = 0
        var successCount: Int { succeeded.count }
    }

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
                summary.succeeded.append(asset)
            } catch {
                summary.failed += 1
            }

            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
        return summary
    }
}
