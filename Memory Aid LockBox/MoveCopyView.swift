//
//  MoveCopyView.swift
//  Memory Aid LockBox
//
//  Internal move/copy between folders (Michael 7/6). Sharing a record "into" the
//  vault is a folder picker: pick a destination folder, then Move (reassign) or
//  Copy (duplicate). One VaultItem model means a move just reassigns the folder
//  and adopts its template, so the record keeps all its data and re-renders under
//  the destination folder's sheet.
//

import SwiftUI
import SwiftData

extension VaultItem {
    /// Adopt a folder template — set the type flags so the item renders under
    /// that template's sheet. Stored field values are untouched (kept, just not
    /// all shown).
    func applyTemplate(_ template: FolderTemplate) {
        isContact = template == .contacts
        isCard = template == .cards
        isCodesAccount = template == .codesAccounts
        isJournal = template == .journal
        isAppointment = template == .appointments
        isReceipt = template == .receipts
    }

    /// A full-fidelity duplicate of this item placed in `folder` — every stored
    /// field copied (used by Copy).
    func duplicated(into folder: Folder?) -> VaultItem {
        let copy = VaultItem(title: title, notes: notes, pin: pin, folder: folder)
        copy.imageData = imageData
        copy.headerVerticalBias = headerVerticalBias
        copy.contactPhone = contactPhone
        copy.contactEmail = contactEmail
        copy.contactAddress = contactAddress
        copy.isContact = isContact
        copy.isBusinessContact = isBusinessContact
        copy.contactWebsite = contactWebsite
        copy.contactHours = contactHours
        copy.contactRelationship = contactRelationship
        copy.isCard = isCard
        copy.cardNumber = cardNumber
        copy.cardExpiry = cardExpiry
        copy.cardCVV = cardCVV
        copy.cardIssuer = cardIssuer
        copy.cardTypeRaw = cardTypeRaw
        copy.cardBarcode = cardBarcode
        copy.isCodesAccount = isCodesAccount
        copy.codeUsername = codeUsername
        copy.codePassword = codePassword
        copy.codeWebsite = codeWebsite
        copy.isJournal = isJournal
        copy.journalDate = journalDate
        copy.isAppointment = isAppointment
        copy.apptProvider = apptProvider
        copy.apptDate = apptDate
        copy.apptPrep = apptPrep
        copy.apptAddress = apptAddress
        copy.apptPhone = apptPhone
        copy.isReceipt = isReceipt
        copy.receiptAddress = receiptAddress
        copy.receiptPhone = receiptPhone
        copy.receiptDate = receiptDate
        copy.receiptItemsJSON = receiptItemsJSON
        copy.receiptSubtotal = receiptSubtotal
        copy.receiptTax = receiptTax
        copy.receiptTotal = receiptTotal
        copy.receiptPaymentType = receiptPaymentType
        copy.receiptCardLast4 = receiptCardLast4
        copy.customValuesJSON = customValuesJSON
        copy.interactionsJSON = interactionsJSON
        copy.significantDatesJSON = significantDatesJSON
        copy.followUpEnabled = followUpEnabled
        copy.followUpIntervalDays = followUpIntervalDays
        return copy
    }
}

struct MoveCopyView: View {
    let item: VaultItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    @State private var target: Folder?

    /// Item folders only (a Photos folder shows a media library, not items).
    private var destinations: [Folder] {
        folders.filter { $0.template != .photos && $0.id != item.folder?.id }
    }

    var body: some View {
        NavigationStack {
            List(selection: $target) {
                Section {
                    ForEach(destinations) { folder in
                        HStack {
                            Image(systemName: folder.iconName).foregroundStyle(.blue)
                            Text(folder.name)
                            Spacer()
                            if target?.id == folder.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { target = folder }
                    }
                } header: {
                    Text("Destination folder")
                } footer: {
                    Text("Move reassigns this record to the folder. Copy leaves the original and duplicates it. Either way it re-renders under the destination folder's fields.")
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 480)
            #endif
            .navigationTitle("Move or Copy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            move()
                        } label: { Label("Move here", systemImage: "arrow.right.doc.on.clipboard") }
                        Button {
                            copy()
                        } label: { Label("Copy here", systemImage: "doc.on.doc") }
                    } label: {
                        Text("Move / Copy").fontWeight(.semibold)
                    }
                    .disabled(target == nil)
                }
            }
        }
    }

    private func move() {
        guard let target else { return }
        item.folder = target
        item.applyTemplate(target.template)
        item.dateModified = Date()
        dismiss()
    }

    private func copy() {
        guard let target else { return }
        let clone = item.duplicated(into: target)
        clone.applyTemplate(target.template)
        modelContext.insert(clone)
        dismiss()
    }
}
