//
//  ContactCRMView.swift
//  Memory Aid LockBox
//
//  The CRM block on a contact's detail (roadmap 010a/b/c): a follow-up nudge, an
//  interaction log, and significant dates that push to Apple Calendar. Data lives
//  on the contact's VaultItem (see CRMSupport). The app never nags on its own —
//  follow-up is opt-in per contact and only surfaces an in-app "overdue" note.
//

import SwiftUI

struct ContactCRMView: View {
    @Bindable var item: VaultItem

    @State private var showAddInteraction = false
    @State private var showAddDate = false
    @State private var dateStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            followUpBlock
            interactionBlock
            datesBlock
        }
    }

    // MARK: - 010c Follow-up

    private var followUpBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Follow-up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            Toggle("Remind me to reach out", isOn: $item.followUpEnabled)
                .font(.system(size: 16))
            if item.followUpEnabled {
                Stepper("Every \(item.followUpIntervalDays) days",
                        value: $item.followUpIntervalDays, in: 1...365)
                    .font(.system(size: 16))
                if item.isFollowUpOverdue {
                    Label(overdueText, systemImage: "bell.badge")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var overdueText: String {
        if let last = item.lastInteractionDate {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            return "Overdue — last contact \(days) day\(days == 1 ? "" : "s") ago"
        }
        return "Overdue — no contact logged yet"
    }

    // MARK: - 010a Interaction log

    private var interactionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Interactions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showAddInteraction = true } label: {
                    Label("Log", systemImage: "plus.circle.fill").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            // Quick-add: one tap logs an interaction right now (dated now, no note).
            // The "Log" button above still opens the full sheet for a note or a
            // back-dated entry.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickLogButton("call", "Called", "phone")
                    quickLogButton("text", "Texted", "message")
                    quickLogButton("email", "Emailed", "envelope")
                    quickLogButton("met", "Met", "person.2")
                }
            }
            if item.interactions.isEmpty {
                Text("No interactions logged yet.").font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                ForEach(item.interactions) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: entry.type)).foregroundStyle(.blue)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.type.capitalized).font(.system(size: 15, weight: .semibold))
                            if !entry.note.isEmpty {
                                Text(entry.note).font(.system(size: 15))
                            }
                            Text(entry.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            item.interactions.removeAll { $0.id == entry.id }
                        } label: { Image(systemName: "trash").font(.system(size: 13)) }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddInteraction) {
            AddInteractionSheet { item.addInteraction($0) }
        }
    }

    /// A single one-tap quick-log button (logs `type` at the current moment).
    private func quickLogButton(_ type: String, _ label: String, _ image: String) -> some View {
        Button {
            item.addInteraction(Interaction(type: type))
        } label: {
            Label(label, systemImage: image).font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    private func icon(for type: String) -> String {
        switch type {
        case "call": return "phone"
        case "text": return "message"
        case "email": return "envelope"
        case "met": return "person.2"
        default: return "circle"
        }
    }

    // MARK: - 010b Significant dates

    private var datesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Significant dates")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showAddDate = true } label: {
                    Label("Add", systemImage: "plus.circle.fill").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            if item.significantDates.isEmpty {
                Text("No dates yet.").font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                ForEach(item.significantDates) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.label.isEmpty ? "Date" : d.label).font(.system(size: 15, weight: .semibold))
                            Text(d.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                            + Text(d.recurring ? " · yearly" : "").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await addDateToCalendar(d) } } label: {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 17))
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            item.significantDates.removeAll { $0.id == d.id }
                        } label: { Image(systemName: "trash").font(.system(size: 13)) }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let dateStatus {
                Text(dateStatus).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showAddDate) {
            AddSignificantDateSheet { var list = item.significantDates; list.append($0); item.significantDates = list }
        }
    }

    private func addDateToCalendar(_ d: SignificantDate) async {
        let title = "\(d.label.isEmpty ? "Date" : d.label) — \(item.title)"
        let ok = await EventKitService.addEvent(
            title: title, date: d.date, durationMinutes: 0,
            annualRecurring: d.recurring)
        dateStatus = ok ? "Added \"\(title)\" to Calendar." : "Couldn't add — check Calendar access in Settings."
    }
}

// MARK: - Add sheets

private struct AddInteractionSheet: View {
    let onAdd: (Interaction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entry = Interaction()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $entry.type) {
                    ForEach(Interaction.types, id: \.self) { Text($0.capitalized).tag($0) }
                }
                DatePicker("When", selection: $entry.date)
                Section("Note") {
                    TextEditor(text: $entry.note).frame(minHeight: 100)
                }
            }
            #if os(macOS)
            .formStyle(.grouped).frame(minWidth: 420, minHeight: 420)
            #endif
            .navigationTitle("Log Interaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(entry); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

private struct AddSignificantDateSheet: View {
    let onAdd: (SignificantDate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = SignificantDate()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label (Birthday, Anniversary…)", text: $value.label)
                DatePicker("Date", selection: $value.date, displayedComponents: .date)
                Toggle("Repeats yearly", isOn: $value.recurring)
            }
            #if os(macOS)
            .formStyle(.grouped).frame(minWidth: 420, minHeight: 300)
            #endif
            .navigationTitle("Significant Date")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(value); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
