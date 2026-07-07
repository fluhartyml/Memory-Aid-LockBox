//
//  CRMSupport.swift
//  Memory Aid LockBox
//
//  Contacts CRM data (roadmap 010a/b/c), stored as JSON collections on the
//  contact's VaultItem (the additive pattern, no new @Model / relationship):
//   • 010a Interaction — a running log of calls/texts/emails/meetings.
//   • 010b SignificantDate — birthdays/anniversaries/etc, pushable to Calendar.
//   • 010c Follow-up — an opt-in "reach out every N days" overdue nudge.
//

import Foundation

/// One logged interaction with a contact (roadmap 010a).
struct Interaction: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var type: String = "call"   // call · text · email · met · other
    var note: String = ""

    static let types = ["call", "text", "email", "met", "other"]
}

/// A significant date for a contact (roadmap 010b).
struct SignificantDate: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String = ""      // Birthday · Anniversary · Met on · custom
    var date = Date()
    var recurring: Bool = true  // birthdays/anniversaries repeat yearly
}

extension VaultItem {
    // MARK: 010a — interaction log (newest first)

    var interactions: [Interaction] {
        get {
            guard let data = interactionsJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Interaction].self, from: data)
            else { return [] }
            return list.sorted { $0.date > $1.date }
        }
        set {
            interactionsJSON = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    func addInteraction(_ interaction: Interaction) {
        var list = interactions
        list.append(interaction)
        interactions = list
    }

    /// Replace an existing interaction (matched by id) with an edited copy —
    /// used when a logged entry is long-pressed to add a note or adjust its
    /// date/time. No-op if the id is no longer present.
    func updateInteraction(_ interaction: Interaction) {
        var list = interactions
        guard let idx = list.firstIndex(where: { $0.id == interaction.id }) else { return }
        list[idx] = interaction
        interactions = list
    }

    // MARK: 010b — significant dates

    var significantDates: [SignificantDate] {
        get {
            guard let data = significantDatesJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([SignificantDate].self, from: data)
            else { return [] }
            return list
        }
        set {
            significantDatesJSON = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    // MARK: 010c — follow-up nudge

    /// The most recent interaction date, or nil if there are none.
    var lastInteractionDate: Date? { interactions.first?.date }

    /// True when follow-up is enabled and the last contact is older than the
    /// chosen interval (or there's been no contact yet).
    var isFollowUpOverdue: Bool {
        guard followUpEnabled else { return false }
        guard let last = lastInteractionDate else { return true }
        let due = Calendar.current.date(byAdding: .day, value: followUpIntervalDays, to: last) ?? last
        return Date() >= due
    }
}
