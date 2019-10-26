//
//  SettingsViewModel.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

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
}
