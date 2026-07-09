//
//  AddFolderView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import SwiftData

struct AddFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortOrder) private var existingFolders: [Folder]

    /// nil = create a new folder · non-nil = edit that folder's name + icon.
    /// The template is NOT editable — changing it would re-route the entry sheet
    /// for items already filed under this folder — so the Template picker is
    /// hidden in edit mode.
    var folderToEdit: Folder? = nil

    @State private var name = ""
    @State private var selectedIcon = "note.text"
    @State private var selectedTemplate: FolderTemplate = .customNotes

    private var isEditing: Bool { folderToEdit != nil }

    let iconOptions = [
        "folder.fill", "creditcard.fill", "lock.fill",
        "person.crop.circle.fill", "photo.fill", "note.text",
        "key.fill", "wifi", "house.fill", "car.fill",
        "airplane", "doc.fill", "globe", "heart.fill",
        "star.fill", "bookmark.fill",
        "text.book.closed.fill", "book.closed.fill",
        "list.bullet.rectangle.portrait.fill",
    ]

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        Picker("Template", selection: $selectedTemplate) {
                            ForEach(FolderTemplate.pickerChoices) { template in
                                Text(template.displayName).tag(template)
                            }
                        }
                        .labelsHidden()
                        .font(.system(size: 18))
                    } header: {
                        Text("Template")
                            .font(.system(size: 16))
                    } footer: {
                        Text("Chooses the entry sheet this folder uses. Custom / Notes is the flexible catch-all.")
                            .font(.system(size: 13))
                    }
                }

                Section {
                    TextField("Folder name", text: $name)
                        .font(.system(size: 18))
                } header: {
                    Text("Name")
                        .font(.system(size: 16))
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? .blue : .clear)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            // Without an explicit style, SwiftUI collapses every
                            // button in a Form cell into ONE tap target, so only a
                            // single glyph ever registers. .plain makes each icon
                            // independently tappable.
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Icon")
                        .font(.system(size: 16))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, minHeight: 480)
            #endif
            .navigationTitle(isEditing ? "Edit Folder" : "New Folder")
            .onAppear {
                // Prefill from the folder being edited so its current name/icon
                // (and template, for the hidden picker's icon suggestion) show.
                if let folder = folderToEdit {
                    name = folder.name
                    selectedIcon = folder.iconName
                    selectedTemplate = folder.template
                }
            }
            .onChange(of: selectedTemplate) { _, newTemplate in
                // Suggest the template's icon; the user can still override it below.
                // Only while creating — editing keeps the folder's existing icon.
                if !isEditing { selectedIcon = newTemplate.defaultIcon }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = folderToEdit {
            // Edit: rename + re-icon only; template and contents are untouched.
            folder.name = trimmed.isEmpty ? folder.name : trimmed
            folder.iconName = selectedIcon
        } else {
            let folder = Folder(
                name: trimmed.isEmpty ? "Untitled" : trimmed,
                iconName: selectedIcon,
                sortOrder: existingFolders.count,
                template: selectedTemplate
            )
            modelContext.insert(folder)
        }
        dismiss()
    }
}
