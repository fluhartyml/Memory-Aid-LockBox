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
    @Environment(VaultLock.self) private var vaultLock

    var body: some View {
        List(selection: $selectedFolder) {
            ForEach(folders) { folder in
                Label {
                    HStack {
                        Text(folder.name)
                            .font(.system(size: 18))
                        Spacer()
                        // Lockbox: every folder reflects the single vault state.
                        Image(systemName: vaultLock.isUnlocked ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(vaultLock.isUnlocked ? Color.secondary : Color.blue)
                            .accessibilityLabel(vaultLock.isUnlocked ? "Unlocked" : "Locked")
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
            ToolbarItem(placement: .principal) {
                // Auto-resizing title: the product name is longer than a large
                // navigation title will display, so draw it as a Text we control
                // and let it shrink to fit instead of truncating with an ellipsis.
                Text("Memory Aid Lockbox")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddFolder = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .inlineNavigationTitle()
    }

    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(folders[index])
        }
    }
}

private extension View {
    /// iOS: force the inline title style so the custom principal title is the only
    /// title shown — otherwise the system large title also renders and truncates.
    /// macOS has no title display mode, so this is a no-op there.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
