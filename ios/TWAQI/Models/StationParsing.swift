//
//  StationParsing.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Reads typed values out of a decoded JSON object, degrading to `nil` for a
/// missing key or a different type (what SwiftyJSON's `.int`/`.string` did).
extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func string(_ key: String) -> String? { self[key] as? String }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func float(_ key: String) -> Float? { (self[key] as? NSNumber)?.floatValue }
}

extension Station {
    /// Builds a `Station` from either `/v1/stations` or the `station` object on
    /// `/v1/historical-pollutants` — the two share a shape.
    ///
    /// Every nested object (`address`, `area`, `additional_info`) is absent for
    /// newer micro-sensor stations, so each field degrades to `nil`.
    static func make(from json: [String: Any]) -> Station {
        let nameEn = json.object("name").string("en")
        let nameZh = json.object("name").string("zh")
        let nameTh = json.object("name").string("th")
        let code = json.string("code") ?? ""

        let imageUrl = json.string("image_url")
        let additionalInfo = json.object("additional_info")

        return Station(
            id: json.int("id") ?? 0,
            // The stations endpoint uses camelCase, the historical one snake_case.
            countryId: json.int("countryId") ?? json.int("country_id") ?? 0,
            countryCode: json.string("countryCode") ?? json.string("country_code") ?? "",
            code: code,
            lat: json.double("lat") ?? 0,
            lon: json.double("lon") ?? 0,
            imageUrl: (imageUrl?.isEmpty ?? true) ? nil : imageUrl,
            name: nameEn ?? nameZh ?? nameTh ?? code,
            nameLocal: nameZh ?? nameTh ?? nameEn ?? code,
            address: json.object("address").string("zh"),
            area: json.object("area").string("en"),
            areaLocal: json.object("area").string("zh"),
            county: additionalInfo.object("county").string("en"),
            countyLocal: additionalInfo.object("county").string("zh"),
            township: additionalInfo.object("township").string("zh"),
            stationTypeRaw: json.string("station_type")
        )
    }
}
