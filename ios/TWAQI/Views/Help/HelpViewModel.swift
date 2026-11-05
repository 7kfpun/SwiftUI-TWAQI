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

            pushDndWindow()

            TrackingManager.logEvent(.setDndNotification, parameters: [
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

    /// Directus takes the window from `SettingsStore`, already saved above.
    private func pushDndWindow() {
        Task { @MainActor in
            DirectusPushMirror.shared.dndChanged()
        }
    }

    /// Turns every station's alerts off: on the device at once, in Directus
    /// as soon as it can be reached.
    func removeAllNotification() {
        FavouriteAlerts.cancelAll()
        TrackingManager.logEvent(.favouriteStationAllRemoved)
        showingAlert = true
    }
}
