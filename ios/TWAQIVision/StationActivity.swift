//
//  StationActivity.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// The payload of a station dragged out of the map or a list. Dropped into
/// the room, it becomes a new station window: that's how a station is pinned.
enum StationActivity {
    /// Also listed under `NSUserActivityTypes` in Info.plist.
    static let type = "com.kfpun.twaqi.station"
    private static let stationIdKey = "stationId"

    static func itemProvider(stationId: Int, title: String) -> NSItemProvider {
        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.userInfo = [stationIdKey: stationId]
        // Routes the new scene to the station window group.
        activity.targetContentIdentifier = type

        let provider = NSItemProvider()
        provider.registerObject(activity, visibility: .all)
        provider.suggestedName = title
        return provider
    }

    static func stationId(from activity: NSUserActivity) -> Int? {
        activity.userInfo?[stationIdKey] as? Int
    }
}
