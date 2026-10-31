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
            pushDndWindow()

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

    /// Directus reads the window (and whether it's on) from `SettingsStore`,
    /// already saved above.
    private func pushDndWindow() {
        Task { @MainActor in
            DirectusPushMirror.shared.dndChanged()
        }
    }

    func removeAllNotification() {
        // Cleared locally at once; Directus is archived in the background and
        // retried until it takes.
        Task { @MainActor in
            DirectusPushMirror.shared.cancelAll()
        }
        TrackingManager.logEvent(eventName: "favourite_station_all_removed")
        showingAlert = true
    }
}
