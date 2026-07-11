//
//  MasterPhotoLibrary.swift
//  Memory Aid LockBox
//
//  The single source of truth for every photo in LockBox (design locked with
//  Michael 2026-07-11, amber proof doc). All photo BYTES live as MediaAssets owned
//  by the master Photos folder ("All Photos"); records and journals keep ordered
//  REFERENCES (asset ids), never their own copies. Each folder surfaces as an
//  album in the master library, derived from those references — no separate album
//  object. Semantics:
//    • add a photo anywhere  → bytes stored once here, caller references the id
//    • remove from a record  → drops the reference only (photo stays in master)
//    • delete in the master  → the real delete (removes it from every album)
//    • delete a folder       → its photos survive here
//

import Foundation
import SwiftData

enum MasterPhotoLibrary {
    /// Find — or create — the one master Photos folder. Prefers template `.photos`,
    /// then a folder literally named "Photos"; creates one if the vault has neither,
    /// so references always have a home even on an odd or pre-Photos vault.
    static func master(in context: ModelContext) -> Folder {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        if let f = folders.first(where: { $0.template == .photos }) { return f }
        if let f = folders.first(where: { $0.name == "Photos" }) { return f }
        let created = Folder(name: "Photos",
                             iconName: FolderTemplate.photos.defaultIcon,
                             template: .photos)
        context.insert(created)
        return created
    }

    /// Store image bytes once in the master library and return the new MediaAsset.
    /// Callers reference `asset.id`; they keep no bytes of their own.
    @discardableResult
    static func store(_ imageData: Data,
                      captured: Date = Date(),
                      fileName: String = "",
                      in context: ModelContext) -> MediaAsset {
        let thumb = MediaThumbnailer.photoThumbnail(from: imageData)
        let asset = MediaAsset(type: .photo,
                               data: imageData,
                               thumbnailData: thumb,
                               originalFileName: fileName,
                               dateCaptured: captured,
                               folder: master(in: context))
        context.insert(asset)
        return asset
    }

    /// Store several photos in order; returns their new ids to reference.
    static func store(_ images: [Data], in context: ModelContext) -> [UUID] {
        images.map { store($0, in: context).id }
    }

    /// Resolve reference ids to their MediaAssets in the SAME order, skipping any
    /// that no longer exist (deleted in master → the reference resolves to nothing).
    static func assets(for ids: [UUID], in context: ModelContext) -> [MediaAsset] {
        guard !ids.isEmpty else { return [] }
        let all = (try? context.fetch(FetchDescriptor<MediaAsset>())) ?? []
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// The ordered image bytes an item's references resolve to — the drop-in
    /// replacement for reading `item.imageData` once a surface is on references.
    static func imageData(for ids: [UUID], in context: ModelContext) -> [Data] {
        assets(for: ids, in: context).compactMap { $0.data }
    }
}
