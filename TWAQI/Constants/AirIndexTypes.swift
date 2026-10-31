//
//  AirIndexTypes.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

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

    func getFormat() -> String {
        let units = [
            "aqi": ".0",
            "pm25": ".0",
            "pm10": ".0",
            "o3": ".1",
            "co": ".2",
            "so2": ".1",
            "no2": ".1",
        ]
        return units[self.rawValue] ?? ""
    }
}
