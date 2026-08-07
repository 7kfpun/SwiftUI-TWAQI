//
//  StationParsing.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import SwiftyJSON

extension Station {
    /// Builds a `Station` from either `/v1/stations` or the `station` object on
    /// `/v1/historical-pollutants` — the two share a shape.
    ///
    /// Every nested object (`address`, `area`, `additional_info`) is absent for
    /// newer micro-sensor stations, so each field degrades to `nil`.
    static func make(from json: JSON) -> Station {
        let nameEn = json["name"]["en"].string
        let nameZh = json["name"]["zh"].string
        let nameTh = json["name"]["th"].string
        let code = json["code"].string ?? ""

        let imageUrl = json["image_url"].string
        let additionalInfo = json["additional_info"]

        return Station(
            id: json["id"].int ?? 0,
            // The stations endpoint uses camelCase, the historical one snake_case.
            countryId: json["countryId"].int ?? json["country_id"].int ?? 0,
            countryCode: json["countryCode"].string ?? json["country_code"].string ?? "",
            code: code,
            lat: json["lat"].double ?? 0,
            lon: json["lon"].double ?? 0,
            imageUrl: (imageUrl?.isEmpty ?? true) ? nil : imageUrl,
            name: nameEn ?? nameZh ?? nameTh ?? code,
            nameLocal: nameZh ?? nameTh ?? nameEn ?? code,
            address: json["address"]["zh"].string,
            area: json["area"]["en"].string,
            areaLocal: json["area"]["zh"].string,
            county: additionalInfo["county"]["en"].string,
            countyLocal: additionalInfo["county"]["zh"].string,
            township: additionalInfo["township"]["zh"].string,
            stationTypeRaw: json["station_type"].string
        )
    }
}
