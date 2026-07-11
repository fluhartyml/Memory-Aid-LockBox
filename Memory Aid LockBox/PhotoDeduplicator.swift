//
//  PhotoDeduplicator.swift
//  Memory Aid LockBox
//
//  Merges byte-identical photos/videos in the master library. For each set of
//  identical copies it keeps ONE survivor, repoints every reference to it
//  (record attachments in VaultItem.assetIDs and album references in
//  Folder.journalAssetIDs), then deletes the redundant copies.
//
//  Visually lossless by construction: only EXACT byte-for-byte duplicates are
//  merged, and every reference is moved to the surviving identical copy — so
//  nothing that was on screen ever disappears; only wasted storage is freed.
//  Idempotent: running it again on a tidy library is a no-op.
//

import Foundation
import SwiftData
import CryptoKit

enum PhotoDeduplicator {
    struct Result {
        /// Number of duplicate SETS found (each set = one photo stored 2+ times).
        var duplicateGroups: Int
        /// Number of redundant copies deleted.
        var removed: Int
    }

    /// Runs against the whole store (all MediaAssets are owned by the master
    /// library). Must run on the main actor — it mutates the default SwiftData
    /// context. Returns a summary for the caller to surface.
    @MainActor
    static func run(in context: ModelContext) -> Result {
        let assets = (try? context.fetch(FetchDescriptor<MediaAsset>())) ?? []
        guard assets.count > 1 else { return Result(duplicateGroups: 0, removed: 0) }

        // Group assets by a content hash of their underlying bytes. Each `bytes`
        // local is released as the loop advances, so only one blob is resident
        // at a time rather than the whole library at once.
        var groups: [Data: [MediaAsset]] = [:]
        for asset in assets {
            guard let bytes = asset.data else { continue }
            let key = Data(SHA256.hash(data: bytes))
            groups[key, default: []].append(asset)
        }

        let dupGroups = groups.values.filter { $0.count > 1 }
        guard !dupGroups.isEmpty else { return Result(duplicateGroups: 0, removed: 0) }

        // Every place a photo can be referenced, loaded once.
        let items = (try? context.fetch(FetchDescriptor<VaultItem>())) ?? []
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []

        // Map each redundant asset id -> the survivor's id. Survivor is the
        // oldest import (stable identity), tie-broken by id so repeat runs pick
        // the same survivor deterministically.
        var remap: [UUID: UUID] = [:]
        var doomed: [MediaAsset] = []
        for group in dupGroups {
            let ordered = group.sorted {
                ($0.dateImported, $0.id.uuidString) < ($1.dateImported, $1.id.uuidString)
            }
            let survivor = ordered[0]
            for extra in ordered.dropFirst() {
                remap[extra.id] = survivor.id
                doomed.append(extra)
            }
        }

        // Repoint references. Duplicate refs WITHIN one holder are left as-is, so
        // a record/album shows exactly the same photos it did before — dedup only
        // changes which stored copy those references resolve to.
        for item in items where item.isOnPhotoReferences {
            if item.assetIDs.contains(where: { remap[$0] != nil }) {
                item.assetIDs = item.assetIDs.map { remap[$0] ?? $0 }
            }
        }
        for folder in folders {
            let refs = folder.journalAssetIDs
            if refs.contains(where: { remap[$0] != nil }) {
                folder.journalAssetIDs = refs.map { remap[$0] ?? $0 }
            }
        }

        // Only after references are safely repointed do we delete the extras.
        for asset in doomed { context.delete(asset) }
        try? context.save()

        return Result(duplicateGroups: dupGroups.count, removed: doomed.count)
    }
}
