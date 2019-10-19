//
//  Constants.swift
//  TWAQI
//
//  Created by kf on 19/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

enum Constants {
    enum AirIndexTypes: String, CaseIterable, Hashable {
        case aqi
        case pm25
        case pm10
        case o3
        case co
        case so2
        case no2

        func toString() -> String {
            let readableStrings = [
                "aqi": "AQI",
                "pm25": "PM2.5",
                "pm10": "PM10",
                "o3": "O3",
                "co": "CO",
                "so2": "SO2",
                "no2": "NO2",
            ]
            return readableStrings[self.rawValue] ?? ""
        }

        func getUnit() -> String {
            let units = [
                "aqi": "",
                "pm25": "μg/m3",
                "pm10": "μg/m3",
                "o3": "ppb",
                "co": "ppm",
                "so2": "ppb",
                "no2": "ppb",
            ]
            return units[self.rawValue] ?? ""
        }
    }

    enum AirStatuses: String, CaseIterable, Hashable {
        case good
        case moderate
        case unhealthyforsensitivegroup
        case unhealthy
        case veryunhealthy
        case hazardous

        func toString() -> String {
            let readableStrings = [
                "good": "Good",
                "moderate": "Moderate",
                "unhealthyforsensitivegroup": "Unhealthy for sensitive groups",
                "unhealthy": "Unhealthy",
                "veryunhealthy": "Very unhealthy",
                "hazardous": "Hazardous",
            ]
            return readableStrings[self.rawValue] ?? ""
        }

        func getColor() -> UInt32 {
            let colors = [
                "good": 0x009866,
                "moderate": 0xFEDE33,
                "unhealthyforsensitivegroup": 0xFE9833,
                "unhealthy": 0xCC0033,
                "veryunhealthy": 0x660098,
                "hazardous": 0x7E2200,
            ]
            return UInt32(colors[self.rawValue] ?? 0xEEEEEE)
        }
    }
}
