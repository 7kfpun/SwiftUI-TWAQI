//
//  TrackingManager.swift
//  TWAQI
//
//  Created by kf on 4/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Firebase
import Foundation

struct TrackingManager {
    static func setUserProperty(key: String, value: String) {
        // Google Analytics
        Analytics.setUserProperty(value, forName: key)
    }

    static func logEvent(eventName: String, parameters: [String: Any] = [:]) {
        print("LogEvent", eventName, parameters)

        // Google Analytics log event.
        Analytics.logEvent(eventName, parameters: parameters)
    }
}
