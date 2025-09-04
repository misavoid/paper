//
//  Item.swift
//  paper
//
//  Created by Misa Nthrop on 04.09.25.
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
