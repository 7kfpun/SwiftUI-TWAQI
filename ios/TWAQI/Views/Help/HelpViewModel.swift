//
//  HelpViewModel.swift
//  TWAQI
//
//  Created by kf on 22/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class HelpViewModel: ObservableObject {
    let settings = SettingsStore()

    /// "HH:mm" in the device's zone, for the analytics labels.
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // These are bound directly to Toggles and DatePickers, so their side effects
    // run in `didSet` — a `willSet` would fire while SwiftUI is still evaluating
    // the view that owns the binding ("Publishing changes from within view updates").

    @Published var dndStartTime: Date {
        didSet {
            settings.dndStartTime = dndStartTime
            pushDndWindow()

            TrackingManager.logEvent(.setDndNotificationStartTime, parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": Self.clock.string(from: dndStartTime),
                "dndEndTime": Self.clock.string(from: dndEndTime),
            ])
        }
    }

    @Published var dndEndTime: Date {
        didSet {
            settings.dndEndTime = dndEndTime
            pushDndWindow()

            TrackingManager.logEvent(.setDndNotificationEndTime, parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": Self.clock.string(from: dndStartTime),
                "dndEndTime": Self.clock.string(from: dndEndTime),
            ])
        }
    }

    @Published var isDndEnabled: Bool {
        didSet {
            settings.isDndEnabled = isDndEnabled

            pushDndWindow()

            TrackingManager.logEvent(.setDndNotification, parameters: [
                "label": isDndEnabled ? "on" : "off",
                "dndStartTime": Self.clock.string(from: dndStartTime),
                "dndEndTime": Self.clock.string(from: dndEndTime),
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
