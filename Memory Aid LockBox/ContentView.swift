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
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @State private var selectedFolder: Folder?
    @State private var selectedItem: VaultItem?
    @State private var showAddFolder = false
    @State private var showAbout = false
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
            }
        } content: {
            if let folder = selectedFolder {
                if folder.name == "Photos" {
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
                    systemImage: "folder",
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
