//
//  Folder.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import Foundation
import SwiftData

@Model
final class Folder {
    // Defaults are required so the model can mirror to CloudKit.
    var name: String = ""
    var iconName: String = "folder.fill"
    var dateCreated: Date = Date()
    var sortOrder: Int = 0

    /// Reserved for possible future per-folder locking. The current build is a
    /// vault-wide lockbox (every folder is gated by VaultLock), so this isn't
    /// read today. Kept (defaulted, CloudKit-safe) to avoid a schema change.
    var requiresAuth: Bool = false

    /// Which specialized template this folder uses (roadmap 001/002). Empty
    /// string = a legacy folder created before templates; it infers its template
    /// from its name (see `template`). Defaulted for CloudKit.
    var templateRaw: String = ""

    /// Configure Fields (roadmap 005a/005b), both folder-level display config.
    /// `hiddenFieldsJSON` = JSON [String] of built-in field keys hidden in this
    /// folder (reversible — hides only, never deletes stored data).
    /// `customFieldsJSON` = JSON [CustomFieldDef] of user-added named fields.
    /// Both defaulted for CloudKit.
    var hiddenFieldsJSON: String = ""
    var customFieldsJSON: String = ""

    /// The folder's template: the stored value when set, otherwise inferred from
    /// the folder name (legacy folders). New folders always store an explicit
    /// value, so the inference only ever applies to pre-template folders.
    var template: FolderTemplate {
        if let stored = FolderTemplate(rawValue: templateRaw) { return stored }
        return FolderTemplate.inferred(fromFolderName: name)
    }

    // CloudKit mirroring requires every relationship to be optional, so these
    // to-many relationships are optional (nil is treated as an empty list).
    @Relationship(deleteRule: .cascade, inverse: \VaultItem.folder)
    var items: [VaultItem]?

    @Relationship(deleteRule: .cascade, inverse: \MediaAsset.folder)
    var mediaAssets: [MediaAsset]?

    init(name: String, iconName: String = "folder.fill", sortOrder: Int = 0, template: FolderTemplate? = nil) {
        self.name = name
        self.iconName = iconName
        self.dateCreated = Date()
        self.sortOrder = sortOrder
        // nil template -> "" -> inferred from name (legacy behavior). New folders
        // pass an explicit template so their sheet is chosen by type, not name.
        self.templateRaw = template?.rawValue ?? ""
    }
}
