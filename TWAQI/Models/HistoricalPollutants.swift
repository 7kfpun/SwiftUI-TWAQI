//
//  HistoricalPollutants.swift
//  TWAQI
//
//  Created by kf on 3/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias HistoricalPollutants = [HistoricalPollutant]

struct HistoricalPollutant: Codable {
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

    private enum CodingKeys: String, CodingKey {
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
