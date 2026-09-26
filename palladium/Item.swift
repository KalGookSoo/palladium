//
//  Item.swift
//  palladium
//
//  Created by doyevskyi on 9/26/26.
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
