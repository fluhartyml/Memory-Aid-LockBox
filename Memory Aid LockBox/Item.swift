//
//  Item.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 6/26/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
