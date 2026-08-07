//
//  Pollutants.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias Pollutants = [Pollutant]

struct Pollutant: Decodable, Hashable {
    let stationId: Int
    let code: String
    let lat: Double
    let lon: Double
    let aqi: Double
    let pm25: Double
    let pm10: Double
    let no2: Double
    let so2: Double
    let co: Double
    let o3: Double
    let windDirection: Double
    let windSpeed: Double
    let publishTime: String

    let name: String
    let nameLocal: String

    // Location detail. All optional — newer micro-sensor stations send `{}`.
    let address: String?
    let area: String?
    let areaLocal: String?
    let county: String?
    let countyLocal: String?
    let township: String?
    let stationType: StationTypes
    let imageUrl: String?

    private enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case code
        case lat
        case lon
        case aqi
        case pm25
        case pm10
        case no2
        case so2
        case co
        case o3
        case windDirection = "wind_direction"
        case windSpeed = "wind_speed"
        case publishTime = "publish_time"
        case imageUrl = "image_url"
        case stationType = "station_type"

        case name
        case address
        case area
        case additionalInfo = "additional_info"
    }

    private enum LangKeys: String, CodingKey {
        case langEn = "en"
        case langZh = "zh"
        case langTh = "th"
    }

    private enum AdditionalInfoKeys: String, CodingKey {
        case county
        case township
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stationId = try values.decode(Int.self, forKey: .stationId)
        code = try values.decodeIfPresent(String.self, forKey: .code) ?? ""
        lat = try values.decode(Double.self, forKey: .lat)
        lon = try values.decode(Double.self, forKey: .lon)
        aqi = try values.decode(Double.self, forKey: .aqi)
        pm25 = try values.decode(Double.self, forKey: .pm25)
        pm10 = try values.decode(Double.self, forKey: .pm10)
        no2 = try values.decode(Double.self, forKey: .no2)
        so2 = try values.decode(Double.self, forKey: .so2)
        co = try values.decode(Double.self, forKey: .co)
        o3 = try values.decode(Double.self, forKey: .o3)
        windDirection = try values.decode(Double.self, forKey: .windDirection)
        windSpeed = try values.decode(Double.self, forKey: .windSpeed)
        publishTime = try values.decode(String.self, forKey: .publishTime)

        let rawImageUrl = try values.decodeIfPresent(String.self, forKey: .imageUrl)
        imageUrl = (rawImageUrl?.isEmpty ?? true) ? nil : rawImageUrl

        stationType = StationTypes(apiValue: try values.decodeIfPresent(String.self, forKey: .stationType))

        // Names. `en` is missing for some stations, so fall back to the Chinese
        // name rather than the literal "Unknown" the old decoder produced.
        let names = try values.nestedContainer(keyedBy: LangKeys.self, forKey: .name)
        let nameZh = try names.decodeIfPresent(String.self, forKey: .langZh)
        let nameTh = try names.decodeIfPresent(String.self, forKey: .langTh)
        let nameEn = try names.decodeIfPresent(String.self, forKey: .langEn)
        name = nameEn ?? nameZh ?? nameTh ?? ""
        nameLocal = nameZh ?? nameTh ?? nameEn ?? ""

        // `address` / `area` / `additional_info` may be `{}`.
        if let addresses = try? values.nestedContainer(keyedBy: LangKeys.self, forKey: .address) {
            address = try addresses.decodeIfPresent(String.self, forKey: .langZh)
        } else {
            address = nil
        }

        if let areas = try? values.nestedContainer(keyedBy: LangKeys.self, forKey: .area) {
            area = try areas.decodeIfPresent(String.self, forKey: .langEn)
            areaLocal = try areas.decodeIfPresent(String.self, forKey: .langZh)
        } else {
            area = nil
            areaLocal = nil
        }

        if let info = try? values.nestedContainer(keyedBy: AdditionalInfoKeys.self, forKey: .additionalInfo) {
            if let counties = try? info.nestedContainer(keyedBy: LangKeys.self, forKey: .county) {
                county = try counties.decodeIfPresent(String.self, forKey: .langEn)
                countyLocal = try counties.decodeIfPresent(String.self, forKey: .langZh)
            } else {
                county = nil
                countyLocal = nil
            }
            if let townships = try? info.nestedContainer(keyedBy: LangKeys.self, forKey: .township) {
                township = try townships.decodeIfPresent(String.self, forKey: .langZh)
            } else {
                township = nil
            }
        } else {
            county = nil
            countyLocal = nil
            township = nil
        }
    }

    func getValue(airIndexType: AirIndexTypes) -> Double {
        switch airIndexType {
        case AirIndexTypes.aqi:
            return self.aqi
        case AirIndexTypes.pm25:
            return self.pm25
        case AirIndexTypes.pm10:
            return self.pm10
        case AirIndexTypes.no2:
            return self.no2
        case AirIndexTypes.so2:
            return self.so2
        case AirIndexTypes.co:
            return self.co
        case AirIndexTypes.o3:
            return self.o3
        }
    }
}

extension Pollutant {
    /// Name in the reader's language, with a fallback that is never "Unknown".
    var displayName: String {
        let preferred = Locale.isChinese ? nameLocal : name
        return preferred.isEmpty ? (code.isEmpty ? "#\(stationId)" : code) : preferred
    }

    /// "Xinyi District, Keelung City" — whichever parts the API supplied.
    var displayLocality: String? {
        let parts = Locale.isChinese
            ? [township, countyLocal]
            : [township, county]
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return joined.isEmpty ? nil : joined.joined(separator: ", ")
    }

    var displayArea: String? {
        let value = Locale.isChinese ? areaLocal : area
        return (value?.isEmpty ?? true) ? nil : value
    }

    var wind: Wind {
        Wind(direction: windDirection, speed: windSpeed)
    }

    /// `"25.129167, 121.760056"`
    var coordinateText: String {
        String(format: "%.6f, %.6f", lat, lon)
    }
}
