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
    let siteName = "test"

    let name: String
    let nameLocal: String

    private enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
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

        case name
    }

    private enum NameLangKeys: String, CodingKey {
        case langEn = "en"
        case langZh = "zh"
        case langTh = "th"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stationId = try values.decode(Int.self, forKey: .stationId)
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
