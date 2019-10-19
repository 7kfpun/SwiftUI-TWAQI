//
//  StationGroups.swift
//  TWAQI
//
//  Created by kf on 19/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias StationGroups = [StationGroup]

struct StationGroup: Hashable, Codable, Identifiable {
    let id = UUID()
    let name: String
    let nameLocal: String
//    let area: String
    let stations: Stations

    private enum CodingKeys: String, CodingKey {
        case name = "county"
        case nameLocal = "county_local"
//        case area = "area"
        case stations = "stations"
    }
}
