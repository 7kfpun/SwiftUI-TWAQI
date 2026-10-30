//
//  WatchReading.swift
//  TWAQIWatch
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// One station's latest reading, as the watch app and its complications keep it.
///
/// `Pollutant` only decodes the API's JSON, so it can't be written back to the
/// shared defaults. This is the encodable subset both targets actually show.
struct WatchReading: Codable, Equatable {
    let stationId: Int
    let code: String
    let name: String
    let nameLocal: String
    let aqi: Double
    let pm25: Double
    let pm10: Double
    let o3: Double
    let co: Double
    let so2: Double
    let no2: Double
    let windDirection: Double
    let windSpeed: Double
    let publishTime: String

    init(_ pollutant: Pollutant) {
        stationId = pollutant.stationId
        code = pollutant.code
        name = pollutant.name
        nameLocal = pollutant.nameLocal
        aqi = pollutant.aqi
        pm25 = pollutant.pm25
        pm10 = pollutant.pm10
        o3 = pollutant.o3
        co = pollutant.co
        so2 = pollutant.so2
        no2 = pollutant.no2
        windDirection = pollutant.windDirection
        windSpeed = pollutant.windSpeed
        publishTime = pollutant.publishTime
    }

    /// Shown in the complication gallery before any real reading exists.
    static let placeholder = WatchReading(
        stationId: 0, code: "Songshan", name: "Songshan", nameLocal: "松山",
        aqi: 42, pm25: 9, pm10: 21, o3: 31.2, co: 0.32, so2: 1.4, no2: 12.5,
        windDirection: 247, windSpeed: 2.6, publishTime: ""
    )

    /// Favourites shown in the Home Screen widget gallery.
    static let placeholderFavourites = [
        WatchReading(
            stationId: -1, code: "Banqiao", name: "Banqiao", nameLocal: "板橋",
            aqi: 58, pm25: 17, pm10: 34, o3: 38.5, co: 0.41, so2: 1.9, no2: 16.1,
            windDirection: 210, windSpeed: 1.8, publishTime: ""
        ),
        WatchReading(
            stationId: -2, code: "Hsinchu", name: "Hsinchu", nameLocal: "新竹",
            aqi: 35, pm25: 8, pm10: 19, o3: 29.7, co: 0.25, so2: 1.1, no2: 9.4,
            windDirection: 30, windSpeed: 4.2, publishTime: ""
        ),
        WatchReading(
            stationId: -3, code: "Tainan", name: "Tainan", nameLocal: "臺南",
            aqi: 104, pm25: 37, pm10: 61, o3: 52.3, co: 0.48, so2: 2.6, no2: 18.8,
            windDirection: 340, windSpeed: 2.1, publishTime: ""
        ),
    ]

    private init(
        stationId: Int, code: String, name: String, nameLocal: String,
        aqi: Double, pm25: Double, pm10: Double, o3: Double, co: Double, so2: Double, no2: Double,
        windDirection: Double, windSpeed: Double, publishTime: String
    ) {
        self.stationId = stationId
        self.code = code
        self.name = name
        self.nameLocal = nameLocal
        self.aqi = aqi
        self.pm25 = pm25
        self.pm10 = pm10
        self.o3 = o3
        self.co = co
        self.so2 = so2
        self.no2 = no2
        self.windDirection = windDirection
        self.windSpeed = windSpeed
        self.publishTime = publishTime
    }

    /// Name in the reader's language, never blank.
    var displayName: String {
        WatchReading.displayName(name: name, nameLocal: nameLocal, code: code, id: stationId)
    }

    static func displayName(name: String, nameLocal: String, code: String, id: Int) -> String {
        let preferred = Locale.isChinese ? nameLocal : name
        return preferred.isEmpty ? (code.isEmpty ? "#\(id)" : code) : preferred
    }

    func value(_ airIndexType: AirIndexTypes) -> Double {
        switch airIndexType {
        case .aqi: return aqi
        case .pm25: return pm25
        case .pm10: return pm10
        case .o3: return o3
        case .co: return co
        case .so2: return so2
        case .no2: return no2
        }
    }

    func status(_ airIndexType: AirIndexTypes = .aqi) -> AirStatuses {
        AirStatuses.checkAirStatus(airIndexType: airIndexType, value: value(airIndexType))
    }

    func formatted(_ airIndexType: AirIndexTypes) -> String {
        value(airIndexType).format(f: airIndexType.getFormat())
    }

    var wind: Wind {
        Wind(direction: windDirection, speed: windSpeed)
    }
}
