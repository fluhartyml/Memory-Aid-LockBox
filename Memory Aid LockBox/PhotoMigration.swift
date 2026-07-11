//
//  PhotoMigration.swift
//  Memory Aid LockBox
//
//  One-time cleanup for vaults created BEFORE the master-photo-library refactor.
//  It pulls each record's legacy inline photo blobs into the master library and
//  switches the record to references, so every existing photo shows up in the
//  Photos folder like newly-added ones do.
//
//  Runs once per device on launch, guarded by a flag. New installs never carried
//  inline blobs, so the pass finds nothing, sets the flag, and never runs again —
//  no user ever has to think about it. Non-destructive: adoptPhotoReferences
//  keeps the original blobs as an unread backup, so a bad run costs nothing.
//

import Foundation
import SwiftData

enum PhotoMigration {
    /// Bump the suffix only if a future schema change ever needs a fresh pass.
    private static let doneKey = "photoReferencesMigrationDone_v1"

    /// Migrate every not-yet-migrated record once. Call AFTER seeding (so the
    /// master folder exists and CloudKit's import has settled) — running against
    /// the momentarily-empty pre-import store would migrate nothing yet still set
    /// the flag. adoptPhotoReferences is per-item idempotent, so even if two
    /// devices both run before syncing, each record only migrates once.
    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let context = container.mainContext
        let items = (try? context.fetch(FetchDescriptor<VaultItem>())) ?? []
        for item in items where !item.usesPhotoReferences {
            item.adoptPhotoReferences(in: context)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
