//
//  NewStations.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias NewStations = [NewStation]

struct NewStation: Codable, Hashable {
    let id: Int
    let countryId: Int
    let code: String
    let lat: Double
    let lon: Double
    var imageUrl: String?

    let name: String
    let nameLocal: String

    private enum CodingKeys: String, CodingKey {
        case id
        case countryId = "country_id"
        case code
        case lat
        case lon
        case imageUrl = "image_url"

        case name
    }

    private enum NameLangKeys: String, CodingKey {
        case langEn = "en"
        case langZh = "zh"
        case langTh = "th"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        countryId = try values.decode(Int.self, forKey: .countryId)
        code = try values.decode(String.self, forKey: .code)
        lat = try values.decode(Double.self, forKey: .lat)
        lon = try values.decode(Double.self, forKey: .lon)
        imageUrl = try values.decode(String.self, forKey: .imageUrl)

        let names = try values.nestedContainer(keyedBy: NameLangKeys.self, forKey: CodingKeys.name)
        if names.contains(.langEn) {
            name = try names.decode(String.self, forKey: .langEn)
        } else {
            name = "Unknown"
        }

        if names.contains(.langZh) {
            nameLocal = try names.decode(String.self, forKey: .langZh)
        } else if names.contains(.langTh) {
            nameLocal = try names.decode(String.self, forKey: .langTh)
        } else {
            nameLocal = "Unknown"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(countryId, forKey: .countryId)
        try container.encode(code, forKey: .code)
    }
}
