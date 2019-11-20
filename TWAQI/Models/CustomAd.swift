//
//  CustomAd.swift
//  TWAQI
//
//  Created by kf on 20/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct CustomAd: Codable, Hashable {
    let id = UUID()
    let name: String
    let impressionRate: Double
    let imageUrl: String
    let destinationUrl: String

    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case impressionRate = "impression_rate"
        case imageUrl = "image_url"
        case destinationUrl = "destination_url"
    }
}
