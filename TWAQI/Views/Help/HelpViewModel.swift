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

    init() {
        self.isDndEnabled = settings.isDndEnabled
        self.dndStartTime = settings.dndStartTime
        self.dndEndTime = settings.dndEndTime
    }
}
