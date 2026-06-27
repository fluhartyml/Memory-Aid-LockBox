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

    @Relationship(deleteRule: .cascade, inverse: \VaultItem.folder)
    var items: [VaultItem] = []

    @Relationship(deleteRule: .cascade, inverse: \MediaAsset.folder)
    var mediaAssets: [MediaAsset] = []

    init(name: String, iconName: String = "folder.fill", sortOrder: Int = 0) {
        self.name = name
        self.iconName = iconName
        self.dateCreated = Date()
        self.sortOrder = sortOrder
    }
}
