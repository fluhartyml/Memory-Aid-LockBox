//
//  QuickTag.swift
//  Memory Aid LockBox
//
//  User-configurable quick-interaction buttons for a contact's CRM log
//  (roadmap 010a refinement). App-wide (not per-contact) — your interaction
//  vocabulary is the same across every contact — stored as JSON in
//  UserDefaults via @AppStorage(QuickTagStore.key). Edited in Settings.
//
//  `typeKey` is the value written to Interaction.type; `iconName` is an SF
//  Symbol. Defaults reproduce the original hardcoded four (Called/Texted/
//  Emailed/Met) with their legacy type keys (call/text/email/met) so existing
//  logged interactions keep mapping to a tag.
//

import Foundation

struct QuickTag: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String = ""          // "Called"
    var typeKey: String = ""        // "call" — stored on Interaction.type
    var iconName: String = "circle" // SF Symbol

    static let defaults: [QuickTag] = [
        QuickTag(label: "Called",  typeKey: "call",  iconName: "phone"),
        QuickTag(label: "Texted",  typeKey: "text",  iconName: "message"),
        QuickTag(label: "Emailed", typeKey: "email", iconName: "envelope"),
        QuickTag(label: "Met",     typeKey: "met",   iconName: "person.2"),
    ]

    /// A stable, human-readable type key derived from a label (lowercased,
    /// trimmed, spaces kept so `.capitalized` still reads well if the tag is
    /// later deleted, e.g. "coffee meetup" → "Coffee Meetup").
    static func slug(from label: String) -> String {
        label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Load/save helpers for the app-wide quick-tag set. Keeping the raw string in
/// @AppStorage (like FieldConfig's JSON columns) and decoding on read.
enum QuickTagStore {
    static let key = "quickTagsJSON"

    static func load(_ json: String) -> [QuickTag] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let tags = try? JSONDecoder().decode([QuickTag].self, from: data)
        else { return QuickTag.defaults }
        return tags
    }

    static func encode(_ tags: [QuickTag]) -> String {
        (try? JSONEncoder().encode(tags))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The tag whose typeKey matches a logged interaction's type, if any.
    static func tag(forType type: String, in tags: [QuickTag]) -> QuickTag? {
        tags.first { $0.typeKey == type }
    }
}
