//
//  TrackingManager.swift
//  TWAQI
//
//  Created by kf on 4/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Amplitude_iOS
import AppCenterAnalytics
import Firebase
import Foundation

struct TrackingManager {
    static func setUserProperty(key: String, value: String) {
        // Google Analytics
        Analytics.setUserProperty(value, forName: key)
    }

    static func logEvent(eventName: String, parameters: [String: Any] = [:]) {
        print("LogEvent", eventName, parameters)

        // Amplitude log event.
        Amplitude.instance().logEvent(eventName, withEventProperties: parameters)

        // Google Analytics log event.
        Analytics.logEvent(eventName, parameters: parameters)

        // App Center Analytics log event.
        let msParameters = parameters.mapValues { value in
            return "\(value)"
        }
        MSAnalytics.trackEvent(eventName, withProperties: msParameters)
    }
}
