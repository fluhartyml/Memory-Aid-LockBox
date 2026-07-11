//
//  Memory_Aid_LockBoxApp.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 6/26/26.
//

import SwiftUI
import SwiftData

@main
struct Memory_Aid_LockBoxApp: App {
    let sharedModelContainer: ModelContainer
    /// Whether the store is mirroring to CloudKit (vs. the local-only fallback).
    /// The seeder needs this to know whether to wait for an initial cloud import.
    let cloudKitAvailable: Bool

    /// Shared lock state for folders that require Face ID. Starts locked, so
    /// protected folders need their own unlock even after the app-entry lock.
    @State private var vaultLock = VaultLock()

    init() {
        let schema = Schema([
            Folder.self,
            VaultItem.self,
            MediaAsset.self,
            VaultMetadata.self,
        ])
        // Sync across the user's devices via CloudKit, using the container
        // declared in the entitlement (iCloud.com.nightgard.Memory-Aid-LockBox).
        // All @Model properties are defaulted/optional, as CloudKit requires.
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            cloudKitAvailable = true
            print("☁️ [LockBox] CloudKit ModelContainer initialized — sync is ON (container iCloud.com.nightgard.Memory-Aid-LockBox).")
        } catch {
            // Fail-safe: if CloudKit mirroring can't start (no iCloud account,
            // container not yet provisioned, offline first launch), fall back to
            // a local-only store rather than crashing. Data is preserved on this
            // device; it simply won't sync until CloudKit becomes available.
            print("⚠️ [LockBox] CloudKit container FAILED — running LOCAL-ONLY (no iCloud sync). Reason: \(error)")
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfiguration])
                cloudKitAvailable = false
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            LockScreenView()
                .environment(vaultLock)
                .task {
                    // Decide whether to create starter folders based on iCloud's
                    // actual state (after import), not the momentarily-empty store.
                    await DefaultFolderSeeder.shared.seedIfNeeded(
                        container: sharedModelContainer,
                        cloudKitAvailable: cloudKitAvailable
                    )
                    // Carry any tags a user set before this version (stored
                    // locally in UserDefaults) onto the CloudKit-synced marker
                    // once. Runs after seeding so the marker exists.
                    QuickTagStore.migrateFromAppStorageIfNeeded(container: sharedModelContainer)
                    // One-time: pull pre-refactor inline photos into the master
                    // library. No-op (then flagged forever) for new installs.
                    // Non-destructive — originals are kept as backup.
                    PhotoMigration.runIfNeeded(container: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
        // Continuity Camera ("Import from iPhone or iPad") removed: with CloudKit
        // sync on, a document captured on the iPhone already appears on the Mac,
        // so the Mac's iPhone-camera import path was redundant. USB/network
        // scanning stays (ScannerSheet).
    }
}
