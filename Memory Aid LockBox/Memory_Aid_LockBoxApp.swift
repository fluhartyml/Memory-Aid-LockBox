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
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
