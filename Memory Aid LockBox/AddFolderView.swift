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
    @State private var name = ""
    @State private var selectedIcon = "note.text"
    @State private var selectedTemplate: FolderTemplate = .customNotes

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
                Section {
                    Picker("Template", selection: $selectedTemplate) {
                        ForEach(FolderTemplate.pickerChoices) { template in
                            Text(template.displayName).tag(template)
                        }
                    }
                    .font(.system(size: 18))
                } header: {
                    Text("Template")
                        .font(.system(size: 16))
                } footer: {
                    Text("Chooses the entry sheet this folder uses. Custom / Notes is the flexible catch-all.")
                        .font(.system(size: 13))
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
            .navigationTitle("New Folder")
            .onChange(of: selectedTemplate) { _, newTemplate in
                // Suggest the template's icon; the user can still override it below.
                selectedIcon = newTemplate.defaultIcon
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let folder = Folder(
                            name: name.isEmpty ? "Untitled" : name,
                            iconName: selectedIcon,
                            sortOrder: existingFolders.count,
                            template: selectedTemplate
                        )
                        modelContext.insert(folder)
                        dismiss()
                    }
                    .font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }
}
