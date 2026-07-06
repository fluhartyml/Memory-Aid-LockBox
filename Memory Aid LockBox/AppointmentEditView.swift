//
//  AppointmentEditView.swift
//  Memory Aid LockBox
//
//  The specialized create sheet for the Appointments template (roadmap 018).
//  Fields: Practice/office (the title) · Provider · Date+Time · Prep/instructions
//  · Address · Phone · Card photo · Notes. "Fill from image" scans an appointment
//  card and fills empty fields (roadmap 004). "Add to Calendar/Reminders" lives
//  on the detail view (roadmap 019). Mirrors CardEditView's structure.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AppointmentEditView: View {
    let folder: Folder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var practice = ""
    @State private var provider = ""
    @State private var date = Date()
    @State private var prep = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var attachedImages: [Data] = []

    @State private var libraryItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var pendingFillAfterScan = false
    @State private var activeSheet: ApptSheet?
    #if os(macOS)
    @State private var showScannerMac = false
    #endif

    private enum ApptSheet: Int, Identifiable {
        case scanner, camera
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Practice / office", $practice)
                    field("Provider (who it's with)", $provider)
                } header: {
                    Text("Appointment").font(.system(size: 16))
                }

                Section {
                    DatePicker("Date & time", selection: $date)
                        .font(.system(size: 17))
                } header: {
                    Text("When").font(.system(size: 16))
                }

                Section {
                    TextEditor(text: $prep)
                        .font(.system(size: 18))
                        .frame(minHeight: 70)
                } header: {
                    Text("Prep / instructions").font(.system(size: 16))
                } footer: {
                    Text("e.g. \"fasting labs 1 week prior.\" A day-before reminder is added when you push to Calendar.")
                        .font(.system(size: 13))
                }

                Section {
                    field("Address", $address)
                    field("Phone", $phone)
                } header: {
                    Text("Contact").font(.system(size: 16))
                }

                Section {
                    TextEditor(text: $notes)
                        .font(.system(size: 18))
                        .frame(minHeight: 60)
                } header: {
                    Text("Notes").font(.system(size: 16))
                }

                Section {
                    if !attachedImages.isEmpty { imageArea }
                    fillFromImageButton
                    captureButtons
                } header: {
                    Text("Card photo").font(.system(size: 16))
                } footer: {
                    Text("\"Fill from image\" scans the appointment card and fills any empty fields.")
                        .font(.system(size: 13))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 680)
            #endif
            .navigationTitle("New Appointment")
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
                        .disabled(practice.isEmpty && provider.isEmpty)
                }
            }
            #if os(iOS)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .scanner:
                    DocumentScannerView { pages in
                        attachedImages.append(contentsOf: pages)
                        if pendingFillAfterScan {
                            pendingFillAfterScan = false
                            if let scanned = pages.first { fillFromImage(from: scanned) }
                        }
                    }
                case .camera:
                    CameraCaptureView { data in attachedImages.append(data) }
                }
            }
            #else
            .sheet(isPresented: $showScannerMac) {
                ScannerSheet { pages in
                    attachedImages.append(contentsOf: pages)
                    if pendingFillAfterScan {
                        pendingFillAfterScan = false
                        if let scanned = pages.first { fillFromImage(from: scanned) }
                    }
                }
            }
            #endif
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        attachedImages.append(data)
                    }
                    libraryItem = nil
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        TextField(label, text: text).font(.system(size: 18))
    }

    // MARK: - Photos

    private var imageArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachedImages.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        thumbnail(at: index)
                        Button(role: .destructive) { attachedImages.remove(at: index) } label: {
                            Image(systemName: "trash").font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func thumbnail(at index: Int) -> some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: attachedImages[index]) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #else
        if let ns = NSImage(data: attachedImages[index]) {
            Image(nsImage: ns).resizable().scaledToFill()
                .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #endif
    }

    private var captureButtons: some View {
        HStack(spacing: 28) {
            #if os(iOS)
            captureButton("Scan", "doc.viewfinder") { activeSheet = .scanner }
            captureButton("Camera", "camera") { activeSheet = .camera }
            #else
            captureButton("Scan", "scanner") { showScannerMac = true }
            #endif
            PhotosPicker(selection: $libraryItem, matching: .images) {
                captureLabel("Library", "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func captureButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { captureLabel(title, symbol) }.buttonStyle(.plain)
    }

    private func captureLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(title).font(.system(size: 13))
        }
        .foregroundStyle(Color.accentColor)
    }

    private var fillFromImageButton: some View {
        Button {
            pendingFillAfterScan = true
            #if os(iOS)
            activeSheet = .scanner
            #else
            showScannerMac = true
            #endif
        } label: {
            HStack(spacing: 8) {
                if isReading { ProgressView() }
                else { Image(systemName: "text.viewfinder").font(.system(size: 18)) }
                Text(isReading ? "Reading…" : "Fill from image").font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(isReading)
    }

    // MARK: - Fill from image

    private func fillFromImage(from image: Data? = nil) {
        guard let first = image ?? attachedImages.first else { return }
        Task {
            isReading = true
            defer { isReading = false }
            guard let card = await CardTextRecognizer.recognize(from: first) else { return }
            let text = card.fullText
            if practice.isEmpty, let suggested = card.suggestedTitle { practice = suggested }
            if notes.isEmpty { notes = text }
        }
    }

    // MARK: - Save

    private func save() {
        let item = VaultItem(title: practice.isEmpty ? "Appointment" : practice,
                             notes: notes,
                             folder: folder)
        item.isAppointment = true
        item.apptProvider = provider
        item.apptDate = date
        item.apptPrep = prep
        item.apptAddress = address
        item.apptPhone = phone
        item.imageData = attachedImages
        modelContext.insert(item)
        dismiss()
    }
}
