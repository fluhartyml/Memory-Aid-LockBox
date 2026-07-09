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
import SwiftData

struct ContactCRMView: View {
    @Bindable var item: VaultItem

    @Query private var vaultMeta: [VaultMetadata]
    @State private var interactionSheet: InteractionSheetMode?
    @State private var showAddDate = false
    @State private var dateStatus: String?

    /// The app-wide quick-interaction tags (editable in Settings), read from the
    /// CloudKit-synced marker so they persist across reinstall and devices.
    private var quickTags: [QuickTag] { QuickTagStore.load(VaultMetadata.quickTagsJSON(from: vaultMeta)) }

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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
            Toggle("Remind me to reach out", isOn: $item.followUpEnabled)
                .font(.system(size: 18))
            if item.followUpEnabled {
                Stepper("Every \(item.followUpIntervalDays) days",
                        value: $item.followUpIntervalDays, in: 1...365)
                    .font(.system(size: 18))
                if item.isFollowUpOverdue {
                    Label(overdueText, systemImage: "bell.badge")
                        .font(.system(size: 17, weight: .semibold))
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { interactionSheet = .add } label: {
                    Label("Log", systemImage: "plus.circle.fill").font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            // Quick-add: one tap logs an interaction right now (dated now, no note).
            // The "Log" button above still opens the full sheet for a note or a
            // back-dated entry.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickTags) { tag in quickLogButton(tag) }
                }
            }
            if item.interactions.isEmpty {
                Text("No interactions logged yet.").font(.system(size: 16)).foregroundStyle(.secondary)
            } else {
                Text("Tap a quick button to log now · long-press an entry to add a note or fix the date")
                    .font(.system(size: 15)).foregroundStyle(.tertiary)
                ForEach(item.interactions) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: entry.type)).foregroundStyle(.blue)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: entry.type)).font(.system(size: 17, weight: .semibold))
                            if !entry.note.isEmpty {
                                Text(entry.note).font(.system(size: 17))
                            }
                            Text(entry.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                .font(.system(size: 16)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            item.interactions.removeAll { $0.id == entry.id }
                        } label: { Image(systemName: "trash").font(.system(size: 16)) }
                        .buttonStyle(.plain)
                    }
                    // Long-press the logged entry to reopen it for a note or a
                    // date/time adjustment (roadmap 010a refinement).
                    .contentShape(Rectangle())
                    .onLongPressGesture { interactionSheet = .edit(entry) }
                }
            }
        }
        .sheet(item: $interactionSheet) { mode in
            switch mode {
            case .add:
                InteractionSheet(title: "Log Interaction", action: "Add") { item.addInteraction($0) }
            case .edit(let entry):
                InteractionSheet(initial: entry, title: "Edit Interaction", action: "Save") { item.updateInteraction($0) }
            }
        }
    }

    /// A single one-tap quick-log button (logs the tag's type at the current moment).
    private func quickLogButton(_ tag: QuickTag) -> some View {
        Button {
            item.addInteraction(Interaction(type: tag.typeKey))
        } label: {
            Label(tag.label, systemImage: tag.iconName).font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    /// Icon for a logged interaction — the matching quick tag's icon, else a
    /// generic dot (e.g. a custom tag that was later removed, or "other").
    private func icon(for type: String) -> String {
        QuickTagStore.tag(forType: type, in: quickTags)?.iconName ?? "circle"
    }

    /// Display name for a logged interaction — the matching quick tag's label,
    /// else the raw type title-cased (graceful if the tag was removed).
    private func label(for type: String) -> String {
        QuickTagStore.tag(forType: type, in: quickTags)?.label ?? type.capitalized
    }

    // MARK: - 010b Significant dates

    private var datesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Significant dates")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showAddDate = true } label: {
                    Label("Add", systemImage: "plus.circle.fill").font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            if item.significantDates.isEmpty {
                Text("No dates yet.").font(.system(size: 16)).foregroundStyle(.secondary)
            } else {
                ForEach(item.significantDates) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.label.isEmpty ? "Date" : d.label).font(.system(size: 17, weight: .semibold))
                            Text(d.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: 16)).foregroundStyle(.secondary)
                            + Text(d.recurring ? " · yearly" : "").font(.system(size: 16)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await addDateToCalendar(d) } } label: {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 19))
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            item.significantDates.removeAll { $0.id == d.id }
                        } label: { Image(systemName: "trash").font(.system(size: 16)) }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let dateStatus {
                Text(dateStatus).font(.system(size: 16)).foregroundStyle(.secondary)
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

// MARK: - Interaction sheet (log new / edit existing)

/// Which mode the single interaction sheet is in — one channel for both "Log"
/// and "Edit" so we never stack two sheets on the same view (the four-stacked-
/// sheets bug lesson). Identifiable so it drives `.sheet(item:)`.
enum InteractionSheetMode: Identifiable {
    case add
    case edit(Interaction)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let entry): return entry.id.uuidString
        }
    }
}

/// Log a new interaction or edit an existing one. Seeded from `initial`;
/// on confirm it hands the (possibly edited) entry back via `onSave`, which
/// decides add-vs-update. The "When" picker covers date AND time.
private struct InteractionSheet: View {
    let title: String
    let action: String
    let onSave: (Interaction) -> Void
    @Query private var vaultMeta: [VaultMetadata]
    @Environment(\.dismiss) private var dismiss
    @State private var entry: Interaction

    init(initial: Interaction = Interaction(),
         title: String = "Log Interaction",
         action: String = "Add",
         onSave: @escaping (Interaction) -> Void) {
        self.title = title
        self.action = action
        self.onSave = onSave
        _entry = State(initialValue: initial)
    }

    /// Type choices = the user's quick tags, plus "Other", plus the entry's
    /// current type if its tag was removed (so it stays selectable when editing).
    private var typeOptions: [(key: String, label: String)] {
        var opts = QuickTagStore.load(VaultMetadata.quickTagsJSON(from: vaultMeta)).map { (key: $0.typeKey, label: $0.label) }
        if !opts.contains(where: { $0.key == "other" }) {
            opts.append((key: "other", label: "Other"))
        }
        if !entry.type.isEmpty && !opts.contains(where: { $0.key == entry.type }) {
            opts.append((key: entry.type, label: entry.type.capitalized))
        }
        return opts
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $entry.type) {
                    ForEach(typeOptions, id: \.key) { opt in Text(opt.label).tag(opt.key) }
                }
                DatePicker("When", selection: $entry.date)
                Section("Note") {
                    TextEditor(text: $entry.note).frame(minHeight: 100)
                }
            }
            #if os(macOS)
            .formStyle(.grouped).frame(minWidth: 420, minHeight: 420)
            #endif
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action) { onSave(entry); dismiss() }.fontWeight(.semibold)
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
