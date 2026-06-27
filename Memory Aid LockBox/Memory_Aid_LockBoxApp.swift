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
        // CloudKit sync is intentionally OFF for now. The "Host in CloudKit"
        // capability is set on the target, but turning on SwiftData↔CloudKit
        // mirroring also requires an iCloud container id AND making every model
        // property optional / defaulted. That's a deliberate follow-up; until
        // then `.none` keeps container creation deterministic (no launch crash).
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
