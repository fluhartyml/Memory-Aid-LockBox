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
        // Two-column split: folders sidebar + a content column that pushes the
        // item detail within its own NavigationStack (instead of a third column).
        // A 2-column split expands on a Max-class phone in landscape, so the
        // folders sidebar now shows on the phone — not just on iPad/Mac. (A
        // 3-column split only expanded at iPad width, collapsing on every phone.)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                folders: folders,
                selectedFolder: $selectedFolder,
                showAddFolder: $showAddFolder
            )
            .toolbar {
                // About + Settings live in a single menu so the narrow sidebar
                // column doesn't overflow its toolbar into a ">>" chevron.
                ToolbarItem(placement: aboutButtonPlacement) {
                    Menu {
                        Button {
                            showAbout = true
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                        Button {
                            // Settings governs the vault's security, so opening it
                            // requires its own Face ID challenge.
                            Task {
                                if await BiometricAuthenticator.authenticate(reason: "Open Settings") {
                                    showSettings = true
                                }
                            }
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            // Give the folders column enough width that names like "Photos"/"Notes"
            // don't truncate and its toolbar button doesn't spill into a ">>".
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            NavigationStack {
                folderContent
                    // Selecting an item in ItemListView sets selectedItem, which
                    // pushes its detail here. Popping clears the binding.
                    .navigationDestination(item: $selectedItem) { item in
                        ItemDetailView(item: item)
                    }
                    .searchable(text: $searchText, prompt: "Search vault")
            }
        }
        .sheet(isPresented: $showAddFolder) {
            AddFolderView()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // Switching folders drops any pushed item detail so we don't linger on an
        // item that belongs to the folder we just left.
        .onChange(of: selectedFolder) { _, _ in
            selectedItem = nil
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

    // The content column: the selected folder's contents, or a placeholder.
    // Lives inside the detail NavigationStack so item detail pushes over it.
    @ViewBuilder
    private var folderContent: some View {
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
            ContentUnavailableView {
                Label {
                    Text("Select a Folder")
                } icon: {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                }
            } description: {
                Text("Choose a folder from the sidebar")
            }
            .font(.system(size: 18))
        }
    }

    private var aboutButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}
