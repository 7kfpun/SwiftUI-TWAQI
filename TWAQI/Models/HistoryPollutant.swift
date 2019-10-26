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
    let aqi: Int
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
}
