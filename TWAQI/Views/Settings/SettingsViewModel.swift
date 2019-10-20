//
//  SettingsViewModel.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation
import OneSignal

class SettingsViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @Published var stationGroups: StationGroups = [] {
        willSet { self.objectWillChange.send() }
    }

    @Published var oneSignalSettings: OneSignalSettings = OneSignalSettings() {
        willSet { self.objectWillChange.send() }
    }

    private(set) lazy var loadStationsFromJSON: () -> Void = {
        DataManager.getDataFromFileWithSuccess { file in
            do {
                let data = try JSONDecoder().decode([String: StationGroups].self, from: file!)
                self.stationGroups = data["stationGroups"]!
                print("self.stationGroups", self.stationGroups)
            } catch {
                print(error)
            }
        }
    }

    private(set) lazy var getSettings: () -> Void = {
        OneSignal.getTags({ tags in
            guard let tags = tags else {
                return
            }
            print("tags - \(tags)")
            var oneSignalSettings = OneSignalSettings()

            for tag in tags {
                guard let key = tag.key as? String else {
                    return
                }

                switch key {
                case "isDndEnabled":
                    guard let value = tag.value as? Bool else {
                        return
                    }
                    oneSignalSettings.isDndEnabled = value
                case "isForecastEnabled":
                    guard let value = tag.value as? Bool else {
                        return
                    }
                    oneSignalSettings.isForecastEnabled = value
                case "dndStartTime":
                    guard let value = tag.value as? Int else {
                        return
                    }
                    oneSignalSettings.dndStartTime = value
                case "dndEndTime":
                    guard let value = tag.value as? Int else {
                        return
                    }
                    oneSignalSettings.dndEndTime = value
                default:
                    print(key, tag.value)
                }
            }

            self.oneSignalSettings = oneSignalSettings
        }, onFailure: { error in
            print("Error getting tags - \(error?.localizedDescription ?? "")")
        })
    }
}
