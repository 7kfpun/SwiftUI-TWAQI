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
            print("Tags sent, \(tags) - \(result ?? [:])")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func disableDnd(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        let tags = ["isDndEnabled", "dndStartTime", "dndEndTime", "isDndStartEarlierThanEnd"]
        OneSignal.deleteTags(tags, onSuccess: { result in
            print("Tags deleted, \(tags) - \(result ?? [:])")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func sendTags(tags: [String: String], completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        OneSignal.sendTags(tags, onSuccess: { result in
            print("Tags sent, \(tags) - \(result ?? [:])")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    /// How long a tag read may take before callers stop waiting. OneSignal
    /// can sit on a read with no answer — offline, or before it has
    /// registered — and the station screen's alert switches wait on it.
    static let readTimeout: TimeInterval = 10

    /// Push settings as OneSignal holds them in this device's tags. Calls
    /// back exactly once, off the main thread: with the settings, or with a
    /// failure when OneSignal fails or doesn't answer within `readTimeout`.
    static func getOneSignalSettings(completionHandler: @escaping (Result<OneSignalSettings, OneSignalError>) -> Void) {
        readOnce(timeout: readTimeout, read: { answer in
            OneSignal.getTags({ tags in
                print("OneSignal tags - \(tags ?? [:])")
                answer(.success(settings(fromTags: tags)))
            }, onFailure: { error in
                print("Error getting tags - \(error?.localizedDescription ?? "None")")
                answer(.failure(.oneSignalError))
            })
        }, completion: completionHandler)
    }

    /// Runs `read` and passes on its first answer, or a failure once
    /// `timeout` has passed without one. Later answers are dropped, so
    /// `completion` runs exactly once.
    static func readOnce<T>(
        timeout: TimeInterval,
        read: (@escaping (Result<T, OneSignalError>) -> Void) -> Void,
        completion: @escaping (Result<T, OneSignalError>) -> Void
    ) {
        let lock = NSLock()
        var answered = false
        let answer: (Result<T, OneSignalError>) -> Void = { result in
            lock.lock()
            let isFirst = !answered
            answered = true
            lock.unlock()
            if isFirst {
                completion(result)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            answer(.failure(.oneSignalError))
        }
        read(answer)
    }

    /// Reads OneSignal's tags into settings. No tags is no settings; a tag
    /// that isn't a string, or a threshold that isn't a number (one set by
    /// hand in the dashboard, say), is skipped rather than failing the rest.
    static func settings(fromTags tags: [AnyHashable: Any]?) -> OneSignalSettings {
        var settings = OneSignalSettings(stationSettings: [:])

        for (key, value) in tags ?? [:] {
            guard let key = key as? String, let value = value as? String else { continue }

            switch key {
            case "isDndEnabled":
                settings.isDndEnabled = value == "true"
            case "dndStartTime":
                settings.dndStartTime = Int(value)
            case "dndEndTime":
                settings.dndEndTime = Int(value)
            default:
                if let stationName = stationName(key, suffix: pollutionSuffix), let threshold = Double(value) {
                    var setting = settings.stationSettings[stationName] ?? OneSignalStationSetting(
                        stationName: stationName,
                        isPollutionNotificationEnabled: false,
                        isCleanlinessNotificationEnabled: false
                    )
                    setting.isPollutionNotificationEnabled = true
                    setting.pollutionTherhold = threshold
                    settings.stationSettings[stationName] = setting
                } else if let stationName = stationName(key, suffix: cleanlinessSuffix), let threshold = Double(value) {
                    var setting = settings.stationSettings[stationName] ?? OneSignalStationSetting(
                        stationName: stationName,
                        isPollutionNotificationEnabled: false,
                        isCleanlinessNotificationEnabled: false
                    )
                    setting.isCleanlinessNotificationEnabled = true
                    setting.cleanlinessTherhold = threshold
                    settings.stationSettings[stationName] = setting
                }
            }
        }

        return settings
    }

    // The legacy `therhold` spelling is what OneSignal's segments filter on.
    private static let pollutionSuffix = "_pollution_therhold"
    private static let cleanlinessSuffix = "_cleanliness_therhold"

    private static func stationName(_ key: String, suffix: String) -> String? {
        guard key.hasSuffix(suffix), key.count > suffix.count else { return nil }
        return String(key.dropLast(suffix.count))
    }
}
