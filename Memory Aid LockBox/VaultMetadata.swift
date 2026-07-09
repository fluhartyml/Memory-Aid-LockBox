//
//  VaultMetadata.swift
//  Memory Aid LockBox
//
//  A tiny, CloudKit-synced marker record that records — once, for the life of a
//  vault — that the starter folders have been set up. The seeder keys off this
//  marker instead of "is the store empty?", which is what lets a user delete
//  every folder and have the vault STAY empty instead of being re-seeded on the
//  next launch (a vault the user emptied still carries this marker).
//
//  Presence of a marker == "this vault has been set up." All attributes are
//  defaulted and there are no relationships, so the model mirrors cleanly to
//  CloudKit and adds without disturbing the existing schema.
//

import Foundation
import SwiftData

@Model
final class VaultMetadata {
    /// True once the starter folders have been seeded (or an existing pre-marker
    /// vault has been adopted). Every marker we create has this set; the seeder
    /// treats the mere presence of a marker as "already set up."
    var hasSeededDefaults: Bool = false

    /// When this vault was first recorded as set-up. Informational.
    var dateCreated: Date = Date()

    /// The app-wide quick-interaction tags (QuickTag) as JSON, stored HERE — on
    /// the CloudKit-synced marker — rather than in @AppStorage/UserDefaults.
    /// UserDefaults is device-local, so a custom tag vanished on reinstall and
    /// never reached the user's other devices; parking it on the synced marker
    /// fixes both. Empty string == "use QuickTag.defaults."
    var quickTagsJSON: String = ""

    init(hasSeededDefaults: Bool = true) {
        self.hasSeededDefaults = hasSeededDefaults
        self.dateCreated = Date()
    }
}

extension VaultMetadata {
    /// The single canonical marker for this vault. If more than one exists
    /// (a transient CloudKit merge across devices), the earliest-created wins so
    /// every device converges on the same record; if none exists yet, one is
    /// created and inserted.
    @MainActor
    static func canonical(in context: ModelContext) -> VaultMetadata {
        let all = (try? context.fetch(FetchDescriptor<VaultMetadata>())) ?? []
        if let earliest = all.min(by: { $0.dateCreated < $1.dateCreated }) {
            return earliest
        }
        let created = VaultMetadata()
        context.insert(created)
        return created
    }

    /// The canonical marker's quick-tag JSON read straight from a @Query result,
    /// no ModelContext needed. Used by read-only consumers so they update live as
    /// CloudKit syncs the tags in.
    static func quickTagsJSON(from all: [VaultMetadata]) -> String {
        all.min(by: { $0.dateCreated < $1.dateCreated })?.quickTagsJSON ?? ""
    }
}
