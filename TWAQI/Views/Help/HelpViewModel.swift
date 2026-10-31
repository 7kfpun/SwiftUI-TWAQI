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
    let settings = SettingsStore()

    // These are bound directly to Toggles and DatePickers, so their side effects
    // run in `didSet` — a `willSet` would fire while SwiftUI is still evaluating
    // the view that owns the binding ("Publishing changes from within view updates").

    @Published var dndStartTime: Date {
        didSet {
            settings.dndStartTime = dndStartTime
            pushDndWindow()

            TrackingManager.logEvent(eventName: "set_dnd_notification_start_time", parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": dndStartTime.convertTo(region: .current).toFormat("HH:mm"),
                "dndEndTime": dndEndTime.convertTo(region: .current).toFormat("HH:mm"),
            ])
        }
    }

    @Published var dndEndTime: Date {
        didSet {
            settings.dndEndTime = dndEndTime
            pushDndWindow()

            TrackingManager.logEvent(eventName: "set_dnd_notification_end_time", parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": dndStartTime.convertTo(region: .current).toFormat("HH:mm"),
                "dndEndTime": dndEndTime.convertTo(region: .current).toFormat("HH:mm"),
            ])
        }
    }

    @Published var isDndEnabled: Bool {
        didSet {
            settings.isDndEnabled = isDndEnabled

            if isDndEnabled {
                pushDndWindow()
            } else {
                OneSignalManager.disableDnd { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
                mirrorDnd()
            }

            TrackingManager.logEvent(eventName: "set_dnd_notification", parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": dndStartTime.convertTo(region: .current).toFormat("HH:mm"),
                "dndEndTime": dndEndTime.convertTo(region: .current).toFormat("HH:mm"),
            ])
        }
    }

    @Published var showingAlert: Bool = false

    init() {
        self.isDndEnabled = settings.isDndEnabled
        self.dndStartTime = settings.dndStartTime
        self.dndEndTime = settings.dndEndTime
    }

    private func pushDndWindow() {
        OneSignalManager.enableDnd(dndStartTime: dndStartTime, dndEndTime: dndEndTime) { result in
            switch result {
            case .success(let result):
                print(result)
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
        mirrorDnd()
    }

    /// Dual-write: Directus gets a copy of the window from `SettingsStore`,
    /// after OneSignal has been sent it.
    private func mirrorDnd() {
        Task { @MainActor in
            DirectusPushMirror.shared.dndChanged()
        }
    }

    func removeAllNotification() {
        // Not tied to OneSignal's answer: the Directus copy is cleared even if
        // reading the tags fails.
        Task { @MainActor in
            DirectusPushMirror.shared.cancelAll()
        }

        OneSignalManager.getOneSignalSettings { [weak self] result in
            // OneSignal calls back off the main thread.
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let settings):
                    self.disabledNotification(stationSettings: settings.stationSettings)
                    TrackingManager.logEvent(eventName: "favourite_station_all_removed")
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
    }

    private func disabledNotification(stationSettings: [String: OneSignalStationSetting]) {
        for (_, stationSetting) in stationSettings {
            OneSignalManager.sendTags(tags: stationSetting.getDisabledTags()) { result in
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
}
