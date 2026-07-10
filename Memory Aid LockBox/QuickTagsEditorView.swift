//
//  QuickTagsEditorView.swift
//  Memory Aid LockBox
//
//  Settings editor for the app-wide quick-interaction tags (QuickTag). Add,
//  rename, re-icon, reorder, or remove the one-tap buttons that appear in a
//  contact's Interactions log. Add and edit share ONE sheet channel
//  (.sheet(item:)) so we never stack two sheets on one view.
//

import SwiftUI
import SwiftData

struct QuickTagsEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vaultMeta: [VaultMetadata]
    @State private var tags: [QuickTag] = []
    @State private var editing: QuickTag?      // new (fresh id) = add · existing = edit

    var body: some View {
        List {
            Section {
                ForEach(tags) { tag in
                    Button { editing = tag } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tag.iconName)
                                .font(.system(size: 19)).foregroundStyle(.blue)
                                .frame(width: 26)
                            Text(tag.label).font(.system(size: 19)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { tags.remove(atOffsets: $0); persist() }
                .onMove { tags.move(fromOffsets: $0, toOffset: $1); persist() }
            } header: {
                Text("Quick tags")
            } footer: {
                Text("The one-tap buttons in a contact's Interactions log. Tap a tag to rename it or change its icon; swipe to remove; drag to reorder.")
            }

            Section {
                Button { editing = QuickTag() } label: {
                    Label("Add a tag", systemImage: "plus.circle.fill")
                }
                if tags != QuickTag.defaults {
                    Button(role: .destructive) {
                        tags = QuickTag.defaults; persist()
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .navigationTitle("Quick tags")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        #endif
        .onAppear { tags = QuickTagStore.load(VaultMetadata.canonical(in: modelContext).quickTagsJSON) }
        .sheet(item: $editing) { tag in
            QuickTagEditSheet(tag: tag) { saved in
                if let i = tags.firstIndex(where: { $0.id == saved.id }) {
                    tags[i] = saved            // edit
                } else {
                    tags.append(saved)         // add
                }
                persist()
            }
        }
    }

    private func persist() {
        VaultMetadata.canonical(in: modelContext).quickTagsJSON = QuickTagStore.encode(tags)
    }
}

// MARK: - Add / edit a single tag

struct QuickTagEditSheet: View {
    let onSave: (QuickTag) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tag: QuickTag

    init(tag: QuickTag, onSave: @escaping (QuickTag) -> Void) {
        self.onSave = onSave
        _tag = State(initialValue: tag)
    }

    /// A curated palette of interaction-flavored SF Symbols.
    private let icons = [
        "phone", "phone.arrow.up.right", "phone.arrow.down.left", "phone.badge.waveform",
        "message", "envelope", "video", "person.2", "hand.wave", "bubble.left.and.bubble.right",
        "calendar", "gift", "cup.and.saucer", "fork.knife", "car", "figure.walk",
        "mappin.and.ellipse", "briefcase", "checkmark.circle", "star", "heart", "bell",
        "doc.text", "creditcard", "cart", "dollarsign.circle", "banknote", "camera", "paperplane",
    ]
    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 10)]

    private var canSave: Bool {
        !tag.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Visited, Coffee, Video call", text: $tag.label)
                }
                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(icons, id: \.self) { name in
                            Image(systemName: name)
                                .font(.system(size: 22))
                                .frame(width: 46, height: 46)
                                .foregroundStyle(tag.iconName == name ? Color.white : Color.primary)
                                .background(tag.iconName == name ? Color.blue : Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { tag.iconName = name }
                                .accessibilityLabel(name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            #if os(macOS)
            .formStyle(.grouped).frame(minWidth: 420, minHeight: 440)
            #endif
            .navigationTitle(tag.typeKey.isEmpty ? "Add Tag" : "Edit Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }.fontWeight(.semibold).disabled(!canSave)
                }
            }
        }
    }

    private func commit() {
        tag.label = tag.label.trimmingCharacters(in: .whitespacesAndNewlines)
        // Brand-new tag (no typeKey yet) → derive a stable key from the label.
        // Existing tags keep their typeKey so already-logged interactions stay
        // linked even after a rename.
        if tag.typeKey.isEmpty {
            tag.typeKey = QuickTag.slug(from: tag.label)
        }
        onSave(tag)
        dismiss()
    }
}
