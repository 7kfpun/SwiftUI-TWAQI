//
//  Countries.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias Countries = [Country]

struct Country: Decodable {
    let id: Int
    let code: String
    let lat: Double
    let lon: Double

    let name: String
    let nameLocal: String

    private enum CodingKeys: String, CodingKey {
        case id
        case code
        case lat
        case lon
        case name
    }

    private enum NameLangKeys: String, CodingKey {
        case langEn = "en"
        case langZh = "zh"
        // case langTh = "th"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        code = try values.decode(String.self, forKey: .code)
        lat = try values.decode(Double.self, forKey: .lat)
        lon = try values.decode(Double.self, forKey: .lon)

        let names = try values.nestedContainer(keyedBy: NameLangKeys.self, forKey: CodingKeys.name)
        if names.contains(.langEn) {
            name = try names.decode(String.self, forKey: .langEn)
        } else {
            name = "Unknown"
        }

        if names.contains(.langZh) {
            nameLocal = try names.decode(String.self, forKey: .langZh)
        } else {
            nameLocal = "Unknown"
        }
    }
}
