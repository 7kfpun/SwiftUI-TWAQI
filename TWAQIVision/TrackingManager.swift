//
//  TrackingManager.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Stand-in for the iOS `TrackingManager`, so shared views that log events
/// compile here. The iOS one reports to Firebase Analytics, which this target
/// doesn't link; events are dropped.
enum TrackingManager {
    static func logEvent(eventName: String, parameters: [String: Any] = [:]) {}
}
