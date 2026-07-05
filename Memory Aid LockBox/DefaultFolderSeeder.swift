//
//  DefaultFolderSeeder.swift
//  Memory Aid LockBox
//
//  Decides — exactly once per launch — whether to create the starter folders,
//  and self-heals the duplicate starter folders that the seed-vs-CloudKit-import
//  race can leave behind.
//
//  The rule (Michael, 6/29/26): base the seed decision on iCloud's ACTUAL state,
//  never on the local store being momentarily empty at launch.
//    • CloudKit already holds any folders/items of any name -> import them,
//      do NOT seed.
//    • CloudKit is genuinely blank on a true first run -> seed the defaults
//      (they then mirror up to iCloud).
//    • No iCloud account at all (local-only fallback) -> seed on empty so the
//      app still works offline.
//
//  Why the seed decision alone is not enough (observed 7/5/26 on a wireless
//  fresh install): after `waitForInitialCloudImport()` returns, SwiftData's
//  main context can still report an EMPTY store even though the CloudKit import
//  is in-flight — `fetchCount` doesn't yet see the just-imported records. So the
//  seeder creates a second full set, and the real folders land a beat later:
//  two of every starter folder. No length of wait fixes this reliably, because
//  "the store looks empty" is inherently racy against sync.
//
//  The durable fix is a SELF-HEALING dedup that runs at launch AND on every
//  CloudKit import completion (so a late-arriving duplicate set gets collapsed
//  the moment it lands). It is safe by construction: it only ever deletes a
//  starter folder that holds NO items and NO media, and always keeps at least
//  one folder per starter — a folder with content is never deleted. This is the
//  same judgment Michael was making by hand, done automatically. Elevated-care
//  data path (mom's passwords vault): no code path can delete a folder that
//  contains anything.
//

import SwiftData
import CoreData

@MainActor
final class DefaultFolderSeeder {
    static let shared = DefaultFolderSeeder()
    private init() {}

    private var hasRun = false
    private var importObserver: NSObjectProtocol?

    /// The 7 fresh-vault starter folders (roadmap 015/016), each carrying its
    /// specialized template so its entry sheet is chosen by type, not name.
    /// Single source of truth for both seeding and dedup.
    private static let starterDefaults: [(name: String, template: FolderTemplate, order: Int)] = [
        ("Cards", .cards, 0),
        ("Codes / Accounts", .codesAccounts, 1),
        ("Photos", .photos, 2),
        ("Notes", .customNotes, 3),
        ("Journal", .journal, 4),
        ("Contacts", .contacts, 5),
        ("Receipts", .receipts, 6),
    ]

    func seedIfNeeded(container: ModelContainer, cloudKitAvailable: Bool) async {
        guard !hasRun else { return }
        hasRun = true

        let context = container.mainContext

        // Install the self-healing observer FIRST, so a duplicate set that
        // arrives from CloudKit later this launch (the race we observed) gets
        // collapsed the moment its import completes.
        if cloudKitAvailable {
            installDedupOnImport(container: container)
        }

        if storeIsEmpty(context) {
            // The local store is empty. If CloudKit is on, its initial import
            // may not have arrived yet — wait for it to finish, then re-check.
            if cloudKitAvailable {
                await waitForInitialCloudImport()
            }
            if storeIsEmpty(context) {
                // Genuinely blank -> create the starter folders.
                seedDefaults(context)
            }
        }

        // Immediate pass: collapses duplicates already present (e.g. a set left
        // in iCloud by a past race) and a seed that raced this launch's import.
        // The observer above handles duplicates that land after this point.
        dedupeDefaultFolders(context)
    }

    /// True only when there are no folders, items, or media assets of any kind.
    private func storeIsEmpty(_ context: ModelContext) -> Bool {
        let folders = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? 0
        if folders > 0 { return false }
        let items = (try? context.fetchCount(FetchDescriptor<VaultItem>())) ?? 0
        if items > 0 { return false }
        let media = (try? context.fetchCount(FetchDescriptor<MediaAsset>())) ?? 0
        return media == 0
    }

    private func seedDefaults(_ context: ModelContext) {
        for (name, template, order) in Self.starterDefaults {
            context.insert(Folder(name: name, iconName: template.defaultIcon, sortOrder: order, template: template))
        }
        try? context.save()
        print("🌱 [LockBox] Cloud was blank — seeded \(Self.starterDefaults.count) starter folders.")
    }

    // MARK: - Self-healing dedup

    /// Collapse duplicate STARTER folders created by the seed-vs-import race.
    ///
    /// Safe by construction:
    ///  • Only folders whose name AND template match a known starter are touched;
    ///    a user-created folder (different name) is never considered.
    ///  • A folder is deleted ONLY when it holds zero items and zero media. A
    ///    folder with any content is always kept — no item can ever be lost.
    ///  • At least one folder per starter is always kept.
    ///  • The keeper is chosen deterministically (earliest dateCreated), so every
    ///    synced device converges on the same survivor.
    private func dedupeDefaultFolders(_ context: ModelContext) {
        let allFolders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        var deletedCount = 0

        for starter in Self.starterDefaults {
            // The exact folders the seeder creates: name AND template both match.
            let group = allFolders.filter { $0.name == starter.name && $0.template == starter.template }
            guard group.count > 1 else { continue }

            let nonEmpty = group.filter { !folderIsEmpty($0) }
            let empty = group.filter { folderIsEmpty($0) }

            if !nonEmpty.isEmpty {
                // A content-bearing folder exists → keep every folder that holds
                // anything (never delete content), delete only the empty twins.
                for folder in empty {
                    guard folderIsEmpty(folder) else { continue } // re-check: never cascade content
                    context.delete(folder)
                    deletedCount += 1
                }
            } else {
                // All duplicates are empty → keep one deterministically, drop the rest.
                let sorted = group.sorted(by: keeperOrder)
                for folder in sorted.dropFirst() {
                    guard folderIsEmpty(folder) else { continue }
                    context.delete(folder)
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            try? context.save()
            print("🧹 [LockBox] Removed \(deletedCount) duplicate starter folder(s) — empty duplicates only; content untouched.")
        }
    }

    private func folderIsEmpty(_ folder: Folder) -> Bool {
        (folder.items?.isEmpty ?? true) && (folder.mediaAssets?.isEmpty ?? true)
    }

    /// Deterministic survivor ordering: earliest-created wins, with a stable
    /// tiebreak so all devices pick the same keeper and converge.
    private func keeperOrder(_ a: Folder, _ b: Folder) -> Bool {
        if a.dateCreated != b.dateCreated { return a.dateCreated < b.dateCreated }
        return String(describing: a.persistentModelID) < String(describing: b.persistentModelID)
    }

    /// Re-run the dedup whenever a CloudKit import completes, so a duplicate set
    /// that lands AFTER the launch pass (the exact case observed) is healed the
    /// moment it arrives. Idempotent and cheap: does nothing when there are no
    /// duplicates.
    private func installDedupOnImport(container: ModelContainer) {
        guard importObserver == nil else { return }
        let context = container.mainContext
        importObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil
            else { return }
            Task { @MainActor in
                self?.dedupeDefaultFolders(context)
            }
        }
    }

    /// Resumes once NSPersistentCloudKitContainer finishes its first `.import`
    /// event, with a grace-period fallback so a blank cloud that posts nothing
    /// still proceeds instead of hanging. (The dedup above is the real safety
    /// net; this wait just reduces how often a duplicate is created at all.)
    private func waitForInitialCloudImport() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let center = NotificationCenter.default
            var observer: NSObjectProtocol?
            var finished = false

            let finish: () -> Void = {
                if finished { return }
                finished = true
                if let observer { center.removeObserver(observer) }
                continuation.resume()
            }

            observer = center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard
                    let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                    event.type == .import,
                    event.endDate != nil
                else { return }
                finish()
            }

            // Wireless first-sync can be slow; give the import a longer runway
            // before falling through (the dedup net covers a false fall-through).
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { finish() }
        }
    }
}
