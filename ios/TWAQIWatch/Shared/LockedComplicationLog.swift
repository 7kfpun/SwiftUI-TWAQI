//
//  LockedComplicationLog.swift
//  TWAQIWatch
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// A free reader's complication set to a Pro style, so it shows the lock
/// (FOX-63). Counted in Firebase as `watch_complication_locked` (FOX-44).
struct LockedComplicationHit: Codable, Hashable {
    /// `ComplicationStyle` raw value.
    let style: String
    /// The WidgetKit family, e.g. `accessoryCircular`.
    let family: String
    /// `IndexOption` raw value.
    let index: String

    /// The Firebase event's parameters. Nothing personal: no station, no place.
    var parameters: [String: String] {
        ["style": style, "family": family, "index": index]
    }
}

/// Gets locked-complication hits from the watch to Firebase, which only the
/// phone has.
///
/// The widget extension can't talk to the phone, so it queues each hit in the
/// app group (`record`); the watch app sends the queue over WatchConnectivity
/// (`drain`, `userInfo(for:)`) and the phone logs it (`hits(fromUserInfo:)`).
/// A setup counts once: timelines rebuild every 30 minutes, and counting each
/// rebuild would measure how long a lock stayed on the face, not how many
/// readers met one.
enum LockedComplicationLog {
    /// The `transferUserInfo` key both sides agree on.
    static let userInfoKey = "watchComplicationLocked"

    /// Hits waiting for the watch app to send them. Bounded: style × family ×
    /// index is 84 setups, and the queue drains whenever the app opens.
    static let maxPending = 100

    private enum Keys {
        static let pending = "lockedComplicationPending"
        static let counted = "lockedComplicationCounted"
    }

    /// Queues `hit` unless this setup was counted before. Returns whether it
    /// was queued.
    @discardableResult
    static func record(_ hit: LockedComplicationHit, in defaults: UserDefaults) -> Bool {
        var counted = Set(defaults.stringArray(forKey: Keys.counted) ?? [])
        let key = "\(hit.style)|\(hit.family)|\(hit.index)"
        guard !counted.contains(key) else { return false }

        var queue = pending(in: defaults)
        guard queue.count < maxPending else { return false }
        queue.append(hit)
        counted.insert(key)
        save(queue, in: defaults)
        defaults.set(counted.sorted(), forKey: Keys.counted)
        return true
    }

    /// Hits not sent yet.
    static func pending(in defaults: UserDefaults) -> [LockedComplicationHit] {
        guard let data = defaults.data(forKey: Keys.pending) else { return [] }
        return (try? JSONDecoder().decode([LockedComplicationHit].self, from: data)) ?? []
    }

    /// Returns the queued hits and empties the queue.
    static func drain(from defaults: UserDefaults) -> [LockedComplicationHit] {
        let queue = pending(in: defaults)
        if !queue.isEmpty {
            defaults.removeObject(forKey: Keys.pending)
        }
        return queue
    }

    /// The payload for `WCSession.transferUserInfo`: property-list types only.
    static func userInfo(for hits: [LockedComplicationHit]) -> [String: Any] {
        [userInfoKey: hits.map(\.parameters)]
    }

    /// Hits in a payload from `userInfo(for:)`; anything else is ignored.
    static func hits(fromUserInfo userInfo: [String: Any]) -> [LockedComplicationHit] {
        guard let entries = userInfo[userInfoKey] as? [[String: String]] else { return [] }
        return entries.compactMap { entry in
            guard let style = entry["style"], let family = entry["family"], let index = entry["index"] else {
                return nil
            }
            return LockedComplicationHit(style: style, family: family, index: index)
        }
    }

    private static func save(_ queue: [LockedComplicationHit], in defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: Keys.pending)
        }
    }
}
