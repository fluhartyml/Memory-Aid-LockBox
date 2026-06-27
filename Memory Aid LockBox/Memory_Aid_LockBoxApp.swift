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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Folder.self,
            VaultItem.self,
            MediaAsset.self,
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
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            // Fail-safe: if CloudKit mirroring can't start (no iCloud account,
            // container not yet provisioned, offline first launch), fall back to
            // a local-only store rather than crashing. Data is preserved on this
            // device; it simply won't sync until CloudKit becomes available.
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [localConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            LockScreenView()
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        // Adds "File → Import from iPhone or iPad → Scan Documents / Take Photo".
        .commands { ImportFromDevicesCommands() }
        #endif
    }
}
