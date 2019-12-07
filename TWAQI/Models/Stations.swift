//
//  Stations.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias Stations = [Station]

struct Station: Codable, Hashable {
    let id: Int
    let countryId: Int
    let countryCode: String
    let code: String
    let lat: Double
    let lon: Double
    var imageUrl: String?

    let name: String
    let nameLocal: String
}
