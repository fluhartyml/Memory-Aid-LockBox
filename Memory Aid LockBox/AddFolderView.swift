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
    @State private var selectedIcon = "folder.fill"

    let iconOptions = [
        "folder.fill", "creditcard.fill", "lock.fill",
        "person.crop.circle.fill", "photo.fill", "note.text",
        "key.fill", "wifi", "house.fill", "car.fill",
        "airplane", "doc.fill", "globe", "heart.fill",
        "star.fill", "bookmark.fill",
    ]

    var body: some View {
        NavigationStack {
            Form {
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
                            sortOrder: existingFolders.count
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
