//
//  StationAlertSetting.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

/// A station's two alerts as the detail page's switches and sliders edit
/// them. The thresholds keep their value while a switch is off, so turning it
/// back on restores the last one. Stored as `StationAlerts` (see
/// `DirectusPushMirror`).
struct StationAlertSetting: Hashable, Codable {
    var isPollutionNotificationEnabled: Bool
    var isCleanlinessNotificationEnabled: Bool
    var pollutionTherhold: Double = 120
    var cleanlinessTherhold: Double = 30

    static let off = StationAlertSetting(isPollutionNotificationEnabled: false, isCleanlinessNotificationEnabled: false)

    init(
        isPollutionNotificationEnabled: Bool,
        isCleanlinessNotificationEnabled: Bool,
        pollutionTherhold: Double = 120,
        cleanlinessTherhold: Double = 30
    ) {
        self.isPollutionNotificationEnabled = isPollutionNotificationEnabled
        self.isCleanlinessNotificationEnabled = isCleanlinessNotificationEnabled
        self.pollutionTherhold = pollutionTherhold
        self.cleanlinessTherhold = cleanlinessTherhold
    }

    /// Switches on for each alert that has a threshold; an alert that's off
    /// keeps the default value for its slider.
    init(_ alerts: StationAlerts) {
        self.init(
            isPollutionNotificationEnabled: alerts.above != nil,
            isCleanlinessNotificationEnabled: alerts.below != nil,
            pollutionTherhold: alerts.above.map(Double.init) ?? 120,
            cleanlinessTherhold: alerts.below.map(Double.init) ?? 30
        )
    }
}
