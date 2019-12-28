//
//  HelpViewModel.swift
//  TWAQI
//
//  Created by kf on 22/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation
import SwiftDate

class HelpViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    let settings = SettingsStore()

    @Published var dndStartTime: Date {
        willSet(newValue) {
            self.objectWillChange.send()

            OneSignalManager.enableDnd(dndStartTime: newValue, dndEndTime: dndEndTime) { result in
                switch result {
                case .success(let result):
                    print(result)
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
            settings.dndStartTime = newValue

            TrackingManager.logEvent(eventName: "set_dnd_notification_start_time", parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": newValue.convertTo(region: .current).toFormat("HH:mm"),
                "dndEndTime": dndEndTime.convertTo(region: .current).toFormat("HH:mm"),
            ])
        }
    }

    @Published var dndEndTime: Date {
        willSet(newValue) {
            self.objectWillChange.send()

            OneSignalManager.enableDnd(dndStartTime: dndStartTime, dndEndTime: newValue) { result in
                switch result {
                case .success(let result):
                    print(result)
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
            settings.dndEndTime = newValue

            TrackingManager.logEvent(eventName: "set_dnd_notification_end_time", parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": dndStartTime.convertTo(region: .current).toFormat("HH:mm"),
                "dndEndTime": newValue.convertTo(region: .current).toFormat("HH:mm"),
            ])
        }
    }

    @Published var isDndEnabled: Bool {
        willSet(newValue) {
            self.objectWillChange.send()

            if newValue {
                OneSignalManager.enableDnd(dndStartTime: dndStartTime, dndEndTime: dndEndTime) { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            } else {
                OneSignalManager.disableDnd { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }
            settings.isDndEnabled = newValue

            TrackingManager.logEvent(eventName: "set_dnd_notification", parameters: [
                "label": newValue ? "on" : "off",
                "dndStartTime": dndStartTime.convertTo(region: .current).toFormat("HH:mm"),
                "dndEndTime": dndEndTime.convertTo(region: .current).toFormat("HH:mm"),
            ])
        }
    }

    @Published var showingAlert: Bool = false {
        willSet { self.objectWillChange.send() }
    }

    init() {
        self.isDndEnabled = settings.isDndEnabled
        self.dndStartTime = settings.dndStartTime
        self.dndEndTime = settings.dndEndTime
    }

    func removeAllNotification() {
        print("")
        OneSignalManager.getOneSignalSettings { result in
            switch result {
            case .success(let result):
                self.disabledNotification(stationSettings: result.stationSettings)
                TrackingManager.logEvent(eventName: "favourite_station_all_removed")
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    private func disabledNotification(stationSettings: [String: OneSignalStationSetting]) {
        for (_, stationSetting) in stationSettings {
            OneSignalManager.sendTags(
                tags: stationSetting.getDisabledTags()
            ) { result in
                switch result {
                case .success(let result):
                    print(result)
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }

        showingAlert = true
    }

    @Published var isCustomAdLoading: Bool = true {
        willSet {
            self.objectWillChange.send()
        }
    }

    var isShowCustomAd: Bool = false
    var customAd: CustomAd?

    private(set) lazy var getCustomAd: () -> Void = {
        APIManager.getCustomAd(position: "help") { result in
            switch result {
            case .success(let customAd):
                self.customAd = customAd
                self.isShowCustomAd = true
            case .failure(let error):
                print(error.localizedDescription)
                self.isShowCustomAd = false
            }

            self.isCustomAdLoading = false
        }
    }
}
