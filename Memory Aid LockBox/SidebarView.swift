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
    @Binding var showAbout: Bool
    @Binding var showSettings: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showResetVaultConfirm: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(VaultLock.self) private var vaultLock

    var body: some View {
        #if os(iOS)
        // Two-row header: the app name gets its own full-width line up top so it
        // stays readable and never crowds into the toolbar, with the controls
        // (menu · add folder · hide/show pane) on a separate row beneath it. The
        // system navigation bar is hidden because this header replaces it.
        VStack(spacing: 0) {
            titleRow
            controlsRow
            Divider()
            folderList
        }
        .toolbar(.hidden, for: .navigationBar)
        #else
        // macOS window is wide — the standard toolbar doesn't crowd or truncate.
        folderList
            .navigationTitle("Memory Aid LockBox")
            .toolbar {
                ToolbarItem(placement: .navigation) { overflowMenu }
                ToolbarItem(placement: .primaryAction) { addFolderButton }
            }
        #endif
    }

    /// Item + media count for a folder. Pulled out of the row's string
    /// interpolation so the type-checker doesn't time out on the optional math.
    private func folderCount(_ folder: Folder) -> Int {
        (folder.items?.count ?? 0) + (folder.mediaAssets?.count ?? 0)
    }

    private var folderList: some View {
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
                        Text("\(folderCount(folder))")
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
    }

    #if os(iOS)
    private var titleRow: some View {
        HStack {
            Text("Memory Aid LockBox")
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var controlsRow: some View {
        HStack(spacing: 20) {
            overflowMenu
            addFolderButton
            Spacer()
            Button {
                withAnimation {
                    columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel("Hide or show sidebar")
        }
        .font(.title3)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    #endif

    private var addFolderButton: some View {
        Button {
            showAddFolder = true
        } label: {
            Label("Add Folder", systemImage: "folder.badge.plus")
        }
    }

    // About + Settings (+ dev reset) in a single menu so the controls row stays
    // compact. Settings is Face-ID gated because it governs vault security.
    private var overflowMenu: some View {
        Menu {
            Button {
                showAbout = true
            } label: {
                Label("About", systemImage: "info.circle")
            }
            Button {
                Task {
                    if await BiometricAuthenticator.authenticate(reason: "Open Settings") {
                        showSettings = true
                    }
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
#if DEBUG
            Divider()
            Button(role: .destructive) {
                // Defer so the Menu fully dismisses before the alert is triggered —
                // flipping the flag inside the menu's dismissal gets swallowed on iPad.
                DispatchQueue.main.async { showResetVaultConfirm = true }
            } label: {
                Label("Reset Vault", systemImage: "trash")
            }
#endif
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(folders[index])
        }
    }
}
