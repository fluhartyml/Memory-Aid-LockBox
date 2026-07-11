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

    @State private var captureDate = Date()
    @State private var dateEdited = false   // true once the user actually changes it
    @State private var didLoad = false
    @State private var hasLocation = false
    @State private var sections: [MetadataService.Section] = []
    // What's currently embedded, so the file is only rewritten when something changed.
    @State private var loadedTitle = ""
    @State private var loadedCaption = ""
    @State private var loadedBody = ""
    @State private var loadedDate: Date?

    private var isPhoto: Bool { asset.mediaType == .photo }

    var body: some View {
        Form {
            // Title + Caption — the short tiers. In the wide layout they sit beside
            // the photo (see MediaViewerView), so only the narrow/sheet form shows
            // them here.
            if mode == .all {
                Section {
                    TextField("Title", text: $asset.title).font(.system(size: 17))
                    TextField("Caption", text: $asset.caption, axis: .vertical)
                        .font(.system(size: 16)).lineLimit(1...3)
                } header: {
                    Text("Title & Caption").font(.system(size: 15))
                } footer: {
                    Text(isPhoto
                         ? "Title and Caption save into the photo — they show in Apple Photos and export with it."
                         : "Stored on this item in the vault.")
                        .font(.system(size: 12))
                }
            }

            if isPhoto {
                // Body — the full entry, no length limit. Inline here on narrow
                // screens; on wide it sits under the Caption beside the photo.
                if mode == .all {
                    Section {
                        TextEditor(text: $asset.notes)
                            .font(.system(size: 16))
                            .frame(minHeight: 160)
                    } header: {
                        Text("Body").font(.system(size: 15))
                    } footer: {
                        Text("The full text, no length limit — embedded in the photo's XMP and travels with the file on export.")
                            .font(.system(size: 12))
                    }
                }

                Section {
                    DatePicker("Captured", selection: $captureDate).font(.system(size: 16))
                } header: {
                    Text("Photo date").font(.system(size: 15))
                } footer: {
                    Text("The photo's own capture date — edit it and it saves into the file.")
                        .font(.system(size: 12))
                }

                if hasLocation {
                    Section {
                        Button(role: .destructive) {
                            removeLocation()
                        } label: {
                            Label("Remove location from photo", systemImage: "location.slash")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    } header: {
                        Text("Location").font(.system(size: 15))
                    } footer: {
                        Text("Strips the GPS coordinates from this photo's metadata.")
                            .font(.system(size: 12))
                    }
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
            } else if mode == .all {
                Section {
                    TextEditor(text: $asset.notes).font(.system(size: 16)).frame(minHeight: 120)
                } header: {
                    Text("Notes").font(.system(size: 15))
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onChange(of: captureDate) { _, _ in
            // Only counts as an edit after the initial load-set, so an untouched
            // photo never gets a fabricated date stamped on close.
            if didLoad { dateEdited = true }
        }
        .onAppear(perform: load)
        .onDisappear(perform: embedIfChanged)
    }

    private func load() {
        guard isPhoto, let data = asset.data else { return }
        let f = MetadataService.editableFields(from: data)
        loadedTitle = f.title; loadedCaption = f.caption; loadedBody = f.body; loadedDate = f.date
        // Surface any embedded text if the vault fields are still empty.
        if asset.title.isEmpty { asset.title = f.title }
        if asset.caption.isEmpty { asset.caption = f.caption }
        if asset.notes.isEmpty { asset.notes = f.body }
        if let d = f.date { captureDate = d }
        hasLocation = MetadataService.hasGPS(in: data)
        sections = MetadataService.sections(from: data)
        didLoad = true
    }

    /// On close, write the three tiers + date into the photo — but only if the
    /// user actually changed something, so we don't rewrite the file for nothing.
    private func embedIfChanged() {
        guard isPhoto, let data = asset.data else { return }
        // nil date = leave the file's date untouched (only write it if edited).
        let newDate: Date? = dateEdited ? captureDate : nil
        let changed = asset.title != loadedTitle
            || asset.caption != loadedCaption
            || asset.notes != loadedBody
            || (dateEdited && captureDate != loadedDate)
        guard changed else { return }
        if let newData = MetadataService.edit(data: data,
                                              title: asset.title,
                                              caption: asset.caption,
                                              body: asset.notes,
                                              date: newDate) {
            asset.data = newData
            loadedTitle = asset.title; loadedCaption = asset.caption
            loadedBody = asset.notes
            if dateEdited { loadedDate = captureDate }
        }
    }

    private func removeLocation() {
        guard let data = asset.data, let stripped = MetadataService.removingGPS(from: data) else { return }
        asset.data = stripped
        sections = MetadataService.sections(from: stripped)
        hasLocation = false
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
                .resizingNavigationTitle("Details")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.font(.system(size: 17, weight: .semibold))
                    }
                }
        }
    }
}
