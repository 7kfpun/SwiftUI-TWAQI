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
    let position: String
    let impressionRate: Int
    let imageUrl: String
    let destinationUrl: String
    let cpc: Double

    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case position = "position"
        case impressionRate = "impression_rate"
        case imageUrl = "image_url"
        case destinationUrl = "destination_url"
        case cpc = "cpc"
    }
}
