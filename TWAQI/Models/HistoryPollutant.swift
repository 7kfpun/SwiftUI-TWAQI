//
//  HistoryPollutant.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias HistoryPollutants = [HistoryPollutant]

struct HistoryPollutant: Codable {
    let stationId: Int
    let aqi: Double
    let pm25: Double
    let pm10: Double
    let no2: Double
    let so2: Double
    let co: Double
    let o3: Double
    let publishTime: String

    private enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case aqi = "AQI"
        case pm25 = "PM25"
        case pm10 = "PM10"
        case no2 = "NO2"
        case so2 = "SO2"
        case co = "CO"
        case o3 = "O3"
        case publishTime = "publish_time"
    }

    func getValue(airIndexType: AirIndexTypes) -> Double {
        switch airIndexType {
        case AirIndexTypes.aqi:
            return Double(self.aqi)
        case AirIndexTypes.pm25:
            return Double(self.pm25)
        case AirIndexTypes.pm10:
            return Double(self.pm10)
        case AirIndexTypes.no2:
            return Double(self.no2)
        case AirIndexTypes.so2:
            return Double(self.so2)
        case AirIndexTypes.co:
            return Double(self.co)
        case AirIndexTypes.o3:
            return Double(self.o3)
        }
    }
}
