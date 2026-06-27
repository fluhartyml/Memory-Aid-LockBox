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
    var name: String
    var iconName: String
    var dateCreated: Date
    var sortOrder: Int

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
