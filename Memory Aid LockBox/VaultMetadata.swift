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

    init(hasSeededDefaults: Bool = true) {
        self.hasSeededDefaults = hasSeededDefaults
        self.dateCreated = Date()
    }
}
