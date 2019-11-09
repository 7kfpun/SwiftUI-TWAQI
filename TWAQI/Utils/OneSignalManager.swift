//
//  OneSignalManager.swift
//  TWAQI
//
//  Created by kf on 26/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import OneSignal
import SwiftDate

enum OneSignalError: Error {
    case oneSignalError
}

enum NotificationTypes: String {
    case pollution
    case cleanliness
}

struct OneSignalManager {
    static func enableForecast(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        let tags = ["isForecastEnabled": "true"]
        OneSignal.sendTags(tags, onSuccess: { result in
            print("Tags sent, \(tags) - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func disableForecast(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        let tags = ["isForecastEnabled"]
        OneSignal.deleteTags(tags, onSuccess: { result in
            print("Tags deleted, \(tags) - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func enableDnd(dndStartTime: Date, dndEndTime: Date, completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        let dndStartTimeCurrentRegion = dndStartTime.convertTo(region: .current)
        let dndEndTimeCurrentRegion = dndEndTime.convertTo(region: .current)

        let tags: [String: Any] = [
            "isDndEnabled": "true",
            "dndStartTime": dndStartTimeCurrentRegion.hour * 60 + dndStartTimeCurrentRegion.minute,
            "dndEndTime": dndEndTimeCurrentRegion.hour * 60 + dndEndTimeCurrentRegion.minute,
            "isDndStartEarlierThanEnd": dndStartTimeCurrentRegion > dndEndTimeCurrentRegion,
        ]
        OneSignal.sendTags(tags, onSuccess: { result in
            print("Tags sent, \(tags) - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func disableDnd(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        let tags = ["isDndEnabled", "dndStartTime", "dndEndTime", "isDndStartEarlierThanEnd"]
        OneSignal.deleteTags(tags, onSuccess: { result in
            print("Tags deleted, \(tags) - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func sendTags(tags: [String: String], completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        OneSignal.sendTags(tags, onSuccess: { result in
            print("Tags sent, \(tags) - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func getOneSignalSettings(completionHandler: @escaping (Result<OneSignalSettings, OneSignalError>) -> Void) {
        var oneSignalSettings = OneSignalSettings(stationSettings: [:])

        OneSignal.getTags({ tags in
            guard let tags = tags else {
                return
            }
            print("OneSignal tags - \(tags)")

            for tag in tags {
                guard let key = tag.key as? String, let value = tag.value as? String else {
                    return
                }

                switch key {
                case "isDndEnabled":
                    oneSignalSettings.isDndEnabled = value == "true"
                case "isForecastEnabled":
                    oneSignalSettings.isForecastEnabled = value == "true"
                case "dndStartTime":
                    oneSignalSettings.dndStartTime = Int(value)
                case "dndEndTime":
                    oneSignalSettings.dndEndTime = Int(value)
                default:
                    if key.contains("_pollution_therhold") {
                        let stationName = key
                            .replacingOccurrences(of: "_pollution_therhold", with: "", options: NSString.CompareOptions.literal, range: nil)

                        if var oneSignalStationSetting = oneSignalSettings.stationSettings[stationName] {
                            oneSignalStationSetting.isPollutionNotificationEnabled = true
                            oneSignalStationSetting.pollutionTherhold = Double(value)!
                            oneSignalSettings.stationSettings[stationName] = oneSignalStationSetting
                        } else {
                            oneSignalSettings.stationSettings[stationName] = OneSignalStationSetting(
                                stationName: stationName,
                                isPollutionNotificationEnabled: true,
                                isCleanlinessNotificationEnabled: false,
                                pollutionTherhold: Double(value)!
                            )
                        }
                    }

                    if key.contains("_cleanliness_therhold") {
                        let stationName = key
                            .replacingOccurrences(of: "_cleanliness_therhold", with: "", options: NSString.CompareOptions.literal, range: nil)

                        if var oneSignalStationSetting = oneSignalSettings.stationSettings[stationName] {
                            oneSignalStationSetting.isCleanlinessNotificationEnabled = true
                            oneSignalStationSetting.cleanlinessTherhold = Double(value)!
                            oneSignalSettings.stationSettings[stationName] = oneSignalStationSetting
                        } else {
                            oneSignalSettings.stationSettings[stationName] = OneSignalStationSetting(
                                stationName: stationName,
                                isPollutionNotificationEnabled: false,
                                isCleanlinessNotificationEnabled: true,
                                pollutionTherhold: Double(value)!
                            )
                        }
                    }
                }
            }

            completionHandler(.success(oneSignalSettings))
        }, onFailure: { error in
            print("Error getting tags - \(error!.localizedDescription)")
            completionHandler(.failure(.oneSignalError))
        })
    }
}
