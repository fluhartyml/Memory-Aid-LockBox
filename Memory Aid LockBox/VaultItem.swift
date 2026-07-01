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
    // Defaults are required so the model can mirror to CloudKit.
    var title: String = ""
    var notes: String = ""
    var pin: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    @Attribute(.externalStorage)
    var imageData: [Data] = []

    /// Vertical framing of the header image (the first attachment) within its
    /// banner: 0 = show the top, 0.5 = centered, 1 = show the bottom. Lets a tall
    /// portrait photo be panned so the right part lands in the banner.
    /// Defaulted for CloudKit; existing notes read back as centered.
    var headerVerticalBias: Double = 0.5

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
