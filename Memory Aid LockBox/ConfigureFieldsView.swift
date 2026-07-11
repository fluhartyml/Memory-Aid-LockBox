//
//  ConfigureFieldsView.swift
//  Memory Aid LockBox
//
//  Per-folder "Configure Fields" (roadmap 005a/005b). REMOVE: toggle a template's
//  built-in fields off to hide them from this folder (reversible — hiding never
//  deletes stored data). ADD: create your own named custom fields on the folder.
//  Built-in field names are never renamed. This is display config; the data model
//  is unchanged (all fields already optional on the one VaultItem).
//

import SwiftUI
import SwiftData

struct ConfigureFieldsView: View {
    @Bindable var folder: Folder
    @Environment(\.dismiss) private var dismiss

    @State private var newFieldName = ""

    var body: some View {
        NavigationStack {
            Form {
                let hideable = folder.template.hideableFields
                if hideable.isEmpty {
                    Section {
                        Text("This folder type has no optional built-in fields to hide.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(hideable, id: \.key) { field in
                            Toggle(field.label, isOn: Binding(
                                get: { !folder.isFieldHidden(field.key) },
                                set: { folder.setField(field.key, hidden: !$0) }
                            ))
                            .font(.system(size: 17))
                        }
                    } header: {
                        Text("Built-in fields").font(.system(size: 16))
                    } footer: {
                        Text("Turn a field off to hide it from this folder. Hiding never deletes data — turn it back on and it returns.")
                            .font(.system(size: 13))
                    }
                }

                Section {
                    ForEach(folder.customFields) { def in
                        HStack {
                            Image(systemName: "tag").foregroundStyle(.secondary)
                            Text(def.name)
                            Spacer()
                            Button(role: .destructive) {
                                folder.customFields.removeAll { $0.id == def.id }
                            } label: {
                                Image(systemName: "trash").font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 17))
                    }
                    HStack {
                        TextField("New field name", text: $newFieldName)
                            .font(.system(size: 17))
                        Button {
                            let name = newFieldName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            folder.customFields.append(CustomFieldDef(name: name))
                            newFieldName = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        .disabled(newFieldName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Custom fields").font(.system(size: 16))
                } footer: {
                    Text("Add your own named fields to every item in this folder.")
                        .font(.system(size: 13))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 560)
            #endif
            .resizingNavigationTitle("Configure Fields")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }
}
