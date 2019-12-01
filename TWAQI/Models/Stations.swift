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
    let lat: Double
    let lon: Double
    var imageUrl: String?

    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case nameLocal = "name_local"
        case lat = "lat"
        case lon = "lon"
        case imageUrl = "image_url"
    }
}
