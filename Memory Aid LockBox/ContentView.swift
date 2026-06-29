//
//  ContentView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        VaultTabView()
    }
}

struct VaultTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(VaultLock.self) private var vaultLock
    @AppStorage("autoLockMinutes") private var autoLockMinutes = 5
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @State private var selectedFolder: Folder?
    @State private var selectedItem: VaultItem?
    @State private var showAddFolder = false
    @State private var showAbout = false
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                folders: folders,
                selectedFolder: $selectedFolder,
                showAddFolder: $showAddFolder
            )
            .toolbar {
                ToolbarItem(placement: aboutButtonPlacement) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: aboutButtonPlacement) {
                    Button {
                        // Settings governs the vault's security, so opening it
                        // requires its own Face ID challenge.
                        Task {
                            if await BiometricAuthenticator.authenticate(reason: "Open Settings") {
                                showSettings = true
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        } content: {
            if let folder = selectedFolder {
                // Lockbox: every folder is gated behind the vault lock.
                if !vaultLock.isUnlocked {
                    LockedFolderView(folder: folder) {
                        vaultLock.unlock(forMinutes: autoLockMinutes)
                    }
                } else if folder.name == "Photos" {
                    MediaLibraryView(folder: folder)
                } else {
                    ItemListView(
                        folder: folder,
                        selectedItem: $selectedItem,
                        searchText: $searchText
                    )
                }
            } else {
                ContentUnavailableView(
                    "Select a Folder",
                    systemImage: "sidebar.leading",
                    description: Text("Choose a folder from the sidebar")
                )
                .font(.system(size: 18))
            }
        } detail: {
            if let item = selectedItem {
                ItemDetailView(item: item)
            } else {
                ContentUnavailableView(
                    "Select an Item",
                    systemImage: "doc.text",
                    description: Text("Choose an item to view its details")
                )
                .font(.system(size: 18))
            }
        }
        .searchable(text: $searchText, prompt: "Search vault")
        .sheet(isPresented: $showAddFolder) {
            AddFolderView()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // When protected folders re-lock (timeout fired), eject the user back to
        // the folder list so nothing sensitive stays on screen mid-view.
        .onChange(of: vaultLock.isUnlocked) { _, unlocked in
            if !unlocked {
                // Whole vault re-locked — eject to the folder list.
                selectedFolder = nil
                selectedItem = nil
            }
        }
        // Re-lock protected folders whenever the app leaves the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                vaultLock.lockNow()
            }
        }
        // Starter folders are seeded by DefaultFolderSeeder (called from the app
        // entry point) once CloudKit's initial import has settled — not here,
        // where the store is momentarily empty before the cloud import lands.
    }

    private var aboutButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}
