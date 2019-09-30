//
//  Station.swift
//  TWAQI
//
//  Created by kf on 30/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct Station: Hashable, Codable, Identifiable {
    let id = UUID()
    var name: String
    var localName: String
    var lon: Double
    var lat: Double
}
