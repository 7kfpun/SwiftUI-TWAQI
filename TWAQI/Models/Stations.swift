//
//  Stations.swift
//  TWAQI
//
//  Created by kf on 30/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias Stations = [Station]

struct Station: Hashable, Codable, Identifiable {
    let id = UUID()
    let name: String
    let localName: String
    let lon: Double
    let lat: Double
}
