//
//  JournalEntryEditView.swift
//  Memory Aid LockBox
//
//  The specialized create sheet for the Journal template (roadmap 009).
//  Fields: Date+Time (auto-stamped to the second, editable so you can place an
//  entry anywhere in the timeline) · Title · Body (long, multiline) · Header
//  image. The entry's OWN Date+Time (`journalDate`) drives the timeline sort —
//  newest first — so editing an old entry never bumps it to the top.
//

import SwiftUI
import SwiftData
import PhotosUI

struct JournalEntryEditView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var entryDate = Date()
    @State private var title = ""
    @State private var body_ = ""
    @State private var headerImage: [Data] = []

    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Group the pickers next to the label instead of pushing them
                    // to the far right of a wide row. One DatePicker already covers
                    // year/month/day (tap the date chip) plus time — no separate
                    // pickers needed.
                    HStack(spacing: 12) {
                        Text("Date & time")
                        DatePicker("Date & time", selection: $entryDate)
                            .labelsHidden()
                        Spacer()
                    }
                    .font(.system(size: 17))
                } header: {
                    Text("When").font(.system(size: 16))
                } footer: {
                    Text("Stamped to the second. Entries sort newest-first by this date — editing later won't move it.")
                        .font(.system(size: 13))
                }

                // Hero image above the title, separating it from the date.
                Section {
                    if let data = headerImage.first { headerThumb(data) }
                    captureButtons
                } header: {
                    Text("Header image").font(.system(size: 16))
                }

                Section {
                    TextField("Title", text: $title).font(.system(size: 18))
                } header: {
                    Text("Title").font(.system(size: 16))
                }

                Section {
                    TextEditor(text: $body_)
                        .font(.system(size: 18))
                        .frame(minHeight: 240)
                } header: {
                    Text("Body").font(.system(size: 16))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 680)
            #endif
            .navigationTitle("New Journal Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 18, weight: .semibold))
                        .disabled(title.isEmpty && body_.isEmpty)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { data in headerImage = [data] }
            }
            #endif
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        headerImage = [data]
                    }
                    libraryItem = nil
                }
            }
        }
    }

    @ViewBuilder
    private func headerThumb(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button(role: .destructive) { headerImage = [] } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22))
                    }
                    .buttonStyle(.plain).padding(6)
                }
        }
        #else
        if let ns = NSImage(data: data) {
            Image(nsImage: ns).resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button(role: .destructive) { headerImage = [] } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22))
                    }
                    .buttonStyle(.plain).padding(6)
                }
        }
        #endif
    }

    private var captureButtons: some View {
        HStack(spacing: 28) {
            #if os(iOS)
            Button { showCamera = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera").font(.system(size: 22))
                    Text("Camera").font(.system(size: 13))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            #endif
            PhotosPicker(selection: $libraryItem, matching: .images) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 22))
                    Text("Library").font(.system(size: 13))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let item = VaultItem(title: title.isEmpty ? "Untitled Entry" : title,
                             notes: body_,
                             folder: folder)
        item.isJournal = true
        item.journalDate = entryDate
        item.imageData = headerImage
        modelContext.insert(item)
        dismiss()
    }
}
