//
//  OneSignalSettings.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct OneSignalSettings: Hashable, Codable {
    var isDndEnabled: Bool?
    var isForecastEnabled: Bool?
    var dndStartTime: Int?
    var dndEndTime: Int?
    var stationSettings: [String: OneSignalStationSetting]
}

struct OneSignalStationSetting: Hashable, Codable {
    var stationName: String
    var isPollutionNotificationEnabled: Bool
    var isCleanlinessNotificationEnabled: Bool
    var pollutionTherhold: Double = 120
    var cleanlinessTherhold: Double = 30

    func getTags() -> [String: String] {
        return [
            "\(stationName)_pollution_therhold": isPollutionNotificationEnabled ? "\(pollutionTherhold)" : "",
            "\(stationName)_cleanliness_therhold": isCleanlinessNotificationEnabled ? "\(cleanlinessTherhold)" : "",
        ]
    }

    func getDisabledTags() -> [String: String] {
        return [
            "\(stationName)": "",
            "\(stationName)_pollution_therhold": "",
            "\(stationName)_cleanliness_therhold": "",
        ]
    }
}
