//
//  DefaultFolderSeeder.swift
//  Memory Aid LockBox
//
//  Decides — exactly once per launch — whether to create the starter folders.
//
//  The rule (Michael, 6/29/26): base the decision on iCloud's ACTUAL state,
//  never on the local store being momentarily empty at launch.
//    • CloudKit already holds any folders/items of any name -> import them,
//      do NOT seed.
//    • CloudKit is genuinely blank on a true first run -> seed the defaults
//      (they then mirror up to iCloud).
//    • No iCloud account at all (local-only fallback) -> seed on empty so the
//      app still works offline.
//
//  The old code seeded in .onAppear whenever `folders.isEmpty`. On a fresh
//  launch the store is empty BEFORE CloudKit's async import lands, so it seeded
//  a duplicate set that then collided with the imported records. This waits for
//  the initial import to finish before deciding, which removes that race.
//

import SwiftData
import CoreData

@MainActor
final class DefaultFolderSeeder {
    static let shared = DefaultFolderSeeder()
    private init() {}

    private var hasRun = false

    func seedIfNeeded(container: ModelContainer, cloudKitAvailable: Bool) async {
        guard !hasRun else { return }
        hasRun = true

        let context = container.mainContext

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
        let defaults: [(String, String, Int)] = [
            ("Cards", "creditcard.fill", 0),
            ("Codes / Accounts", "lock.fill", 1),
            ("Photos", "photo.fill", 2),
            ("Notes", "note.text", 3),
            // A journal is just a notes-style folder (item list), so it needs no
            // special handling — only "Photos"/"Cards" are special-cased.
            ("Journal", "book.closed.fill", 4),
        ]
        for (name, icon, order) in defaults {
            context.insert(Folder(name: name, iconName: icon, sortOrder: order))
        }
        try? context.save()
        print("🌱 [LockBox] Cloud was blank — seeded \(defaults.count) starter folders.")
    }

    /// Resumes once NSPersistentCloudKitContainer finishes its first `.import`
    /// event, with a grace-period fallback so a blank cloud that posts nothing
    /// still proceeds instead of hanging.
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { finish() }
        }
    }
}
