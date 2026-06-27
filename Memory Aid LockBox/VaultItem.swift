//
//  VaultItem.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import Foundation
import SwiftData

@Model
final class VaultItem {
    var title: String
    var notes: String
    var pin: String
    var dateCreated: Date
    var dateModified: Date

    @Attribute(.externalStorage)
    var imageData: [Data] = []

    var folder: Folder?

    init(title: String, notes: String = "", pin: String = "", folder: Folder? = nil) {
        self.title = title
        self.notes = notes
        self.pin = pin
        self.dateCreated = Date()
        self.dateModified = Date()
        self.folder = folder
    }
}
