//
//  Item.swift
//  PulseBar
//
//  Created by lingjhf on 2026/6/12.
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
