//
//  MediaDetailsView.swift
//  Memory Aid LockBox
//
//  The info panel for a vault photo/video (roadmap 014b/c): per-item Title +
//  Notes (stored on the MediaAsset), plus a metadata viewer that shows EXIF/TIFF/
//  GPS and lets the user deliberately edit the description and capture date. The
//  app never auto-strips or auto-injects — edits happen only here, on the user's
//  action, and preserve every other tag.
//
//  The Form content lives in `MediaDetailsForm` so it can be shown two ways:
//  as a standalone sheet (`MediaDetailsView`) or inline beside the photo in the
//  adaptive viewer (MediaViewerView) — the layout that flows between a folded
//  and unfolded iPhone. See [[reference_iphone_fold_adaptive_layout]].
//

import SwiftUI

/// The reusable details Form (Title/Notes + editable metadata + EXIF list).
/// No navigation chrome — the container supplies it.
struct MediaDetailsForm: View {
    /// `all` = Title/Notes + metadata (used inline on narrow screens and in the
    /// standalone sheet). `metadataOnly` = editable metadata + EXIF, used in the
    /// wide iPad panel where Title/Notes live prominently below the photo instead.
    enum Mode { case all, metadataOnly }

    @Bindable var asset: MediaAsset
    var mode: Mode = .all

    @State private var description = ""
    @State private var captureDate = Date()
    @State private var hasDate = false
    @State private var sections: [MetadataService.Section] = []
    @State private var metadataStatus: String?

    private var isPhoto: Bool { asset.mediaType == .photo }

    var body: some View {
        Form {
            if mode == .all {
                Section {
                    TextField("Title", text: $asset.title).font(.system(size: 17))
                    TextEditor(text: $asset.notes)
                        .font(.system(size: 16))
                        .frame(minHeight: 80)
                } header: {
                    Text("Title & Notes").font(.system(size: 15))
                } footer: {
                    Text("Stored on this item in the vault — separate from the file's own metadata.")
                        .font(.system(size: 12))
                }
            }

            if isPhoto {
                Section {
                    TextField("Description", text: $description, axis: .vertical)
                        .font(.system(size: 16))
                    Toggle("Set capture date", isOn: $hasDate).font(.system(size: 16))
                    if hasDate {
                        DatePicker("Captured", selection: $captureDate)
                            .font(.system(size: 16))
                    }
                    Button {
                        saveMetadata()
                    } label: {
                        Label("Save metadata to photo", systemImage: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    if let metadataStatus {
                        Text(metadataStatus).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Editable metadata").font(.system(size: 15))
                } footer: {
                    Text("Writes into the photo's own EXIF/TIFF, preserving all other tags. Deliberate edit only.")
                        .font(.system(size: 12))
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            HStack(alignment: .top) {
                                Text(row.key).font(.system(size: 13)).foregroundStyle(.secondary)
                                Spacer()
                                Text(row.value).font(.system(size: 13))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } header: {
                        Text(section.title).font(.system(size: 15))
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear(perform: loadMetadata)
    }

    private func loadMetadata() {
        guard isPhoto, let data = asset.data else { return }
        let fields = MetadataService.editableFields(from: data)
        description = fields.description
        if let d = fields.date { captureDate = d; hasDate = true }
        sections = MetadataService.sections(from: data)
    }

    private func saveMetadata() {
        guard let data = asset.data else { return }
        if let newData = MetadataService.edit(
            data: data,
            description: description.isEmpty ? nil : description,
            date: hasDate ? captureDate : nil) {
            asset.data = newData
            sections = MetadataService.sections(from: newData)
            metadataStatus = "Saved into the photo."
        } else {
            metadataStatus = "Couldn't write metadata to this file."
        }
    }
}

/// Standalone sheet wrapper around `MediaDetailsForm`.
struct MediaDetailsView: View {
    @Bindable var asset: MediaAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MediaDetailsForm(asset: asset)
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 600)
                #endif
                .navigationTitle("Details")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.font(.system(size: 17, weight: .semibold))
                    }
                }
        }
    }
}
