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
    @State private var showAsk = false
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // The reset button + dialog are DEBUG-gated; the state is always declared so
    // SidebarView's binding stays valid in release builds.
    @State private var showResetVaultConfirm = false

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
                showAddFolder: $showAddFolder,
                showAbout: $showAbout,
                showSettings: $showSettings,
                columnVisibility: $columnVisibility,
                showResetVaultConfirm: $showResetVaultConfirm
            )
            // Give the folders column enough width that names like "Photos"/"Notes"
            // don't truncate.
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            NavigationStack {
                folderContent
                    // Selecting an item in ItemListView sets selectedItem, which
                    // pushes its detail here. Popping clears the binding. The
                    // detail is a pager so you can swipe left/right (iOS) or use
                    // prev/next (macOS) between the folder's records without
                    // popping back to the list. Siblings are snapshotted in the
                    // list's own order at push time.
                    .navigationDestination(item: $selectedItem) { item in
                        RecordPagerView(items: orderedSiblings(of: item), current: item)
                    }
                    .searchable(text: $searchText, prompt: "Search vault")
                    .toolbar {
                        // Natural-language recall over the vault. Only offered
                        // while unlocked, since it reads across every entry.
                        if vaultLock.isUnlocked {
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    showAsk = true
                                } label: {
                                    Label("Ask", systemImage: "sparkle.magnifyingglass")
                                }
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showAsk) {
            AskVaultView { item in
                // Jump to the tapped source entry.
                selectedFolder = item.folder
                selectedItem = item
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
#if DEBUG
        // An .alert (not .confirmationDialog) so it presents reliably on iPad even
        // when triggered from the sidebar's overflow Menu. The destructive action
        // is additionally gated behind a Face ID / Touch ID challenge — a wipe of
        // the whole vault must never run on a single stray tap.
        .alert(
            "Reset the entire vault?",
            isPresented: $showResetVaultConfirm
        ) {
            Button("Wipe & Reseed", role: .destructive) {
                Task {
                    let ok = await BiometricAuthenticator.authenticate(
                        reason: "Confirm your identity to wipe and reseed the entire vault."
                    )
                    guard ok else { return }
                    selectedItem = nil
                    selectedFolder = nil
                    DefaultFolderSeeder.shared.devResetAndReseed(container: modelContext.container)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("DEV ONLY: deletes every folder, item, and photo — including the seed-once marker in iCloud — then recreates the starter folders, reproducing a genuine first install. You'll be asked to confirm with Face ID / Touch ID.")
        }
#endif
        // Switching folders drops any pushed item detail so we don't linger on an
        // item that belongs to the folder we just left.
        .onChange(of: selectedFolder) { _, _ in
            selectedItem = nil
        }
        // Changing the auto-lock timeout in Settings re-arms the running window
        // so the new value takes effect immediately (not just on the next unlock).
        .onChange(of: autoLockMinutes) { _, newValue in
            vaultLock.reschedule(forMinutes: newValue)
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
            } else if folder.template == .photos {
                MediaLibraryView(folder: folder)
            } else if folder.template == .photoJournal {
                PhotoJournalView(folder: folder)
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

    /// The item's folder-mates in the SAME order ItemListView shows them (journal
    /// = newest journalDate first, everything else = newest dateModified first),
    /// so paging follows the list you were just looking at. Snapshotted at push
    /// time. Search filtering isn't applied here — paging walks the whole folder.
    private func orderedSiblings(of item: VaultItem) -> [VaultItem] {
        let source = item.folder?.items ?? []
        let sorted = (item.folder?.template == .journal)
            ? source.sorted { $0.journalDate > $1.journalDate }
            : source.sorted { $0.dateModified > $1.dateModified }
        return sorted
    }
}

// MARK: - Record pager (swipe between records)

/// Pages through a folder's records — swipe left/right on iOS, prev/next arrows
/// on macOS — starting at the tapped record. Pushed into the detail
/// NavigationStack, so each ItemDetailView supplies its own title and toolbar;
/// this only adds the paging (and the macOS arrows). Mirrors MediaPagerView.
/// (Michael, 2026-07-11)
struct RecordPagerView: View {
    let items: [VaultItem]
    // VaultItem is a SwiftData @Model, so its identity is a PersistentIdentifier
    // (not a UUID like MediaAsset) — that's what tags/selects the paged records.
    @State private var selection: PersistentIdentifier

    init(items: [VaultItem], current: VaultItem) {
        self.items = items.isEmpty ? [current] : items
        _selection = State(initialValue: current.id)
    }

    var body: some View {
        content
        #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(!canStep(-1))
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(!canStep(1))
                }
            }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ForEach(items) { item in
                ItemDetailView(item: item).tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        if let item = items.first(where: { $0.id == selection }) {
            ItemDetailView(item: item)
        } else {
            ContentUnavailableView("Record Unavailable", systemImage: "doc")
        }
        #endif
    }

    #if os(macOS)
    private var currentIndex: Int? { items.firstIndex { $0.id == selection } }
    private func canStep(_ d: Int) -> Bool {
        guard let i = currentIndex else { return false }
        return items.indices.contains(i + d)
    }
    private func step(_ d: Int) {
        guard let i = currentIndex, items.indices.contains(i + d) else { return }
        selection = items[i + d].id
    }
    #endif
}
