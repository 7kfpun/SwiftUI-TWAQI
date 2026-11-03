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

            TrackingManager.logEvent(.setDndNotificationStartTime, parameters: [
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

            TrackingManager.logEvent(.setDndNotificationEndTime, parameters: [
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

            TrackingManager.logEvent(.setDndNotification, parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": dndStartTime.convertTo(region: .current).toFormat("HH:mm"),
                "dndEndTime": dndEndTime.convertTo(region: .current).toFormat("HH:mm"),
            ])
        }
    }

    @Published var showingAlert: Bool = false

    /// "Cancel all" didn't reach OneSignal, so nothing was cancelled.
    @Published private(set) var cancelAllFailed = false

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

    /// Turns every station's alerts off: OneSignal first, the Directus copy
    /// only once OneSignal has taken it. Says whether it worked either way.
    func removeAllNotification() {
        FavouriteAlerts.cancelAll { [weak self] cancelled in
            guard let self = self else { return }
            if cancelled {
                TrackingManager.logEvent(.favouriteStationAllRemoved)
            }
            self.cancelAllFailed = !cancelled
            self.showingAlert = true
        }
    }
}
