//
//  MasterPhotoPickerView.swift
//  Memory Aid LockBox
//
//  Pick photos already in the master Photos library to reference into a Photo
//  Journal (the "Add from Library" flow). Multi-select grid; returns the chosen
//  ids in display order. Photos already in the journal are excluded from the
//  grid. No bytes are copied — the journal only gains references.
//

import SwiftUI
import SwiftData

struct MasterPhotoPickerView: View {
    let master: Folder
    let excluding: Set<UUID>            // ids already referenced by the journal
    let onAdd: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 4)]

    private var assets: [MediaAsset] {
        (master.mediaAssets ?? [])
            .filter { !excluding.contains($0.id) }
            .sorted { $0.dateImported > $1.dateImported }
    }

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    ContentUnavailableView("Nothing to Add",
                        systemImage: "photo.on.rectangle",
                        description: Text("Every photo in your master library is already in this journal."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(assets) { tile($0) }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("Add from Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? "Add" : "Add (\(selection.count))") {
                        onAdd(assets.filter { selection.contains($0.id) }.map(\.id))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    private func tile(_ asset: MediaAsset) -> some View {
        let isSelected = selection.contains(asset.id)
        return MediaThumbnailImage(data: asset.thumbnailData ?? asset.data)
            .aspectRatio(1, contentMode: .fill)
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : .white)
                    .background(Circle().fill(.black.opacity(0.3)))
                    .padding(4)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected { selection.remove(asset.id) } else { selection.insert(asset.id) }
            }
    }
}
