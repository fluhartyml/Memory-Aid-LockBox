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
                ItemListView(
                    folder: folder,
                    selectedItem: $selectedItem,
                    searchText: $searchText
                )
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
        .onAppear {
            seedDefaultFolders()
        }
    }

    private var aboutButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    private func seedDefaultFolders() {
        guard folders.isEmpty else { return }
        let defaults: [(String, String, Int)] = [
            ("Cards", "creditcard.fill", 0),
            ("Codes / Accounts", "lock.fill", 1),
            ("Photos", "photo.fill", 2),
            ("Notes", "note.text", 3),
        ]
        for (name, icon, order) in defaults {
            let folder = Folder(name: name, iconName: icon, sortOrder: order)
            modelContext.insert(folder)
        }
    }
}
