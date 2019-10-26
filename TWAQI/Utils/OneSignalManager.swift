//
//  OneSignalManager.swift
//  TWAQI
//
//  Created by kf on 26/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import OneSignal

enum OneSignalError: Error {
    case oneSignalError
}

struct OneSignalManager {
    static func enableForecast(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        OneSignal.sendTag("isForecastEnabled", value: "true", onSuccess: { result in
            print("Tags sent, [isForecastEnabled: true] - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func disableForecast(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        OneSignal.sendTag("isForecastEnabled", value: "", onSuccess: { result in
            print("Tags sent, [isForecastEnabled: ''] - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func enableDnd(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        OneSignal.sendTag("isDndEnabled", value: "true", onSuccess: { result in
            print("Tags sent, [isDndEnabled: true] - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func disableDnd(completionHandler: @escaping (Result<Bool, OneSignalError>) -> Void) {
        OneSignal.deleteTags(["isDndEnabled", "dndStartTime", "dndEndTime"], onSuccess: { result in
            print("Tags sent, [isDndEnabled: ''] - \(result!)")
            completionHandler(.success(true))
        }) { error in
            print("Error sending tags: \(error?.localizedDescription ?? "None")")
            completionHandler(.failure(.oneSignalError))
        }
    }

    static func getOneSignalSettings(completionHandler: @escaping (Result<OneSignalSettings, OneSignalError>) -> Void) {
        var oneSignalSettings = OneSignalSettings()

        OneSignal.getTags({ tags in
            guard let tags = tags else {
                return
            }
            print("OneSignal tags - \(tags)")

            for tag in tags {
                guard let key = tag.key as? String else {
                    return
                }

                switch key {
                case "isDndEnabled":
                    guard let value = tag.value as? String else {
                        return
                    }
                    oneSignalSettings.isDndEnabled = value == "true"
                case "isForecastEnabled":
                    guard let value = tag.value as? String else {
                        return
                    }
                    oneSignalSettings.isForecastEnabled = value == "true"
                case "dndStartTime":
                    guard let value = tag.value as? String else {
                        return
                    }
                    oneSignalSettings.dndStartTime = Int(value)
                case "dndEndTime":
                    guard let value = tag.value as? String else {
                        return
                    }
                    oneSignalSettings.dndEndTime = Int(value)
                default:
                    print(key, tag.value)
                }
            }
        }, onFailure: { error in
            print("Error getting tags - \(error!.localizedDescription)")
            completionHandler(.failure(.oneSignalError))
        })

        completionHandler(.success(oneSignalSettings))
    }
}
