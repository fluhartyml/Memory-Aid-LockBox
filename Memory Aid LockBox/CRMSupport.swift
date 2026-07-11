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
    // Frozen snapshot of the quick tag's label + icon, captured when the tag is
    // later edited or deleted, so a logged interaction keeps how it looked at
    // the time — editing/deleting a tag must NOT rewrite past log entries
    // (Michael, 2026-07-10: "auto-update is fine, just not for the history").
    // Nil until frozen; while nil the display falls back to a live tag lookup.
    var label: String? = nil
    var iconName: String? = nil

    static let types = ["call", "text", "email", "met", "other"]
}

/// A significant date for a contact (roadmap 010b).
struct SignificantDate: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String = ""      // Birthday · Anniversary · Met on · custom
    var date = Date()           // carries time as well as day (Michael, 2026-07-11)
    var recurring: Bool = true  // birthdays/anniversaries repeat yearly
    var note: String = ""       // optional description (added 2026-07-11)
    // Local-notification lead time, in MINUTES BEFORE the date/time. nil = no
    // reminder; 0 = notify at the moment it arrives. Scheduled via NotificationService
    // (added 2026-07-11 — Michael wanted per-date lead time).
    var reminderLeadMinutes: Int? = nil

    init() {}

    // Custom decode so dates saved before `note`/`reminderLeadMinutes` existed still
    // load: synthesized Codable throws `keyNotFound` on a missing key even when the
    // property has a default, which would drop every pre-existing entry.
    enum CodingKeys: String, CodingKey { case id, label, date, recurring, note, reminderLeadMinutes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(UUID.self,   forKey: .id) ?? UUID()
        label     = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        date      = try c.decodeIfPresent(Date.self,   forKey: .date) ?? Date()
        recurring = try c.decodeIfPresent(Bool.self,   forKey: .recurring) ?? true
        note      = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        reminderLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes)
    }

    /// The selectable lead-time presets: (display label, minutes-before). `nil`
    /// minutes = "Off". Shared by the picker and the row's reminder badge.
    static let leadOptions: [(label: String, minutes: Int?)] = [
        ("Off", nil),
        ("At time", 0),
        ("15 minutes before", 15),
        ("30 minutes before", 30),
        ("1 hour before", 60),
        ("1 day before", 1_440),
        ("1 week before", 10_080),
    ]

    /// Short human label for the row badge, e.g. "1 day before"; nil when off.
    var reminderDescription: String? {
        guard let lead = reminderLeadMinutes else { return nil }
        switch lead {
        case 0:       return "At time"
        case 60:      return "1 hour before"
        case 1_440:   return "1 day before"
        case 10_080:  return "1 week before"
        default:
            if lead % 1_440 == 0 { return "\(lead / 1_440) days before" }
            if lead % 60 == 0    { return "\(lead / 60) hours before" }
            return "\(lead) minutes before"
        }
    }
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
