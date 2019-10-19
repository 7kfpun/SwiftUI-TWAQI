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
    let nameLocal: String
    let lon: Double
    let lat: Double
    var imageUrl: String?

    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case nameLocal = "name_local"
        case lon = "lon"
        case lat = "lat"
        case imageUrl = "imageUrl"
    }
}
