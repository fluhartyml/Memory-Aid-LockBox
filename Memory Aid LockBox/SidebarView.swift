//
//  SidebarView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    let folders: [Folder]
    @Binding var selectedFolder: Folder?
    @Binding var showAddFolder: Bool
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List(selection: $selectedFolder) {
            ForEach(folders) { folder in
                Label {
                    HStack {
                        Text(folder.name)
                            .font(.system(size: 18))
                        Spacer()
                        Text("\((folder.items?.count ?? 0) + (folder.mediaAssets?.count ?? 0))")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: folder.iconName)
                        .foregroundStyle(.blue)
                }
                .tag(folder)
                .draggable(folder.name)
            }
            .onDelete(perform: deleteFolders)
        }
        .navigationTitle("Memory Aid Lockbox")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddFolder = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(folders[index])
        }
    }
}
