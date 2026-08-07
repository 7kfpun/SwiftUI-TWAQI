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

    // Location detail. Optional with defaults so the memberwise initialiser
    // stays source-compatible and older cached JSON still decodes.
    var address: String?
    var area: String?
    var areaLocal: String?
    var county: String?
    var countyLocal: String?
    var township: String?
    var stationTypeRaw: String?
}

extension Station {
    /// Name in the reader's language, never blank and never "Unknown".
    var displayName: String {
        let preferred = Locale.isChinese ? nameLocal : name
        return preferred.isEmpty ? (code.isEmpty ? "#\(id)" : code) : preferred
    }

    /// "Xinyi District, Keelung City" — whichever parts the API supplied.
    var displayLocality: String? {
        let parts = Locale.isChinese ? [township, countyLocal] : [township, county]
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return joined.isEmpty ? nil : joined.joined(separator: ", ")
    }

    /// Air-quality region, used to group the station list.
    var displayArea: String? {
        let value = Locale.isChinese ? areaLocal : area
        return (value?.isEmpty ?? true) ? nil : value
    }

    var stationType: StationTypes {
        StationTypes(apiValue: stationTypeRaw)
    }
}
