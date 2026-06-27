//
//  AddItemView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct AddItemView: View {
    let folder: Folder
    @Binding var initialImages: [Data]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var pin = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []
    @State private var hasLoadedInitial = false
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var viewingImage: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.system(size: 18))
                } header: {
                    Text("Name")
                        .font(.system(size: 16))
                }

                // Scanned images section
                if !attachedImages.isEmpty {
                    Section {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(attachedImages.indices, id: \.self) { index in
                                    thumbnailView(at: index)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text("Scans")
                                .font(.system(size: 16))
                            Spacer()
                            #if os(iOS)
                            Button {
                                showScanner = true
                            } label: {
                                Label("Add Page", systemImage: "doc.viewfinder")
                                    .font(.system(size: 14))
                            }
                            #endif
                        }
                    }
                }

                Section {
                    TextField("PIN, code, or password", text: $pin)
                        .font(.system(size: 20, design: .monospaced))
                        #if os(iOS)
                        .keyboardType(folder.name == "Cards" ? .numberPad : .default)
                        #endif
                } header: {
                    Text("PIN / Code")
                        .font(.system(size: 16))
                }

                Section {
                    TextEditor(text: $notes)
                        .font(.system(size: 18))
                        .frame(minHeight: 80)
                } header: {
                    Text("Notes")
                        .font(.system(size: 16))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 560)
            #endif
            .navigationTitle("New Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newItem = VaultItem(
                            title: title.isEmpty ? "Untitled" : title,
                            notes: notes,
                            pin: pin,
                            folder: folder
                        )
                        newItem.imageData = attachedImages
                        modelContext.insert(newItem)
                        dismiss()
                    }
                    .font(.system(size: 18, weight: .semibold))
                }
            }
            .onAppear {
                if !hasLoadedInitial {
                    attachedImages = initialImages
                    hasLoadedInitial = true
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showScanner) {
                DocumentScannerView { pages in
                    attachedImages.append(contentsOf: pages)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { data in
                    attachedImages.append(data)
                }
            }
            .sheet(item: $viewingImage) { imageData in
                ImageViewerView(imageData: imageData)
            }
            #endif
        }
    }

    @ViewBuilder
    private func thumbnailView(at index: Int) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: attachedImages[index]) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    viewingImage = attachedImages[index]
                }
                .contextMenu {
                    Button(role: .destructive) {
                        attachedImages.remove(at: index)
                    } label: {
                        Label("Remove Page", systemImage: "trash")
                    }
                }
        }
        #endif
    }
}

// Make Data identifiable for sheet(item:)
extension Data: @retroactive Identifiable {
    public var id: Int { hashValue }
}
