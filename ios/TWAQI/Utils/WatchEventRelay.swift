//
//  WatchEventRelay.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import WatchConnectivity

/// Logs to Firebase what the watch sends over WatchConnectivity: the watch has
/// no Firebase of its own. Today that is a free reader's complication set to a
/// Pro style (`LockedComplicationLog`, FOX-63).
final class WatchEventRelay: NSObject, WCSessionDelegate {
    static let shared = WatchEventRelay()

    /// Call once at launch, after `TrackingManager.applyExclusionAtLaunch()`.
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the saved favourites to the watch as its application context:
    /// only the latest list matters, and it is delivered even when the watch
    /// app isn't running. Alerts are not sent (FOX-174).
    func sendFavourites(_ ids: [Int]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(WatchFavourites.context(for: ids))
    }

    /// Logs every hit in `userInfo`; anything else in it is ignored.
    static func logEvents(fromUserInfo userInfo: [String: Any], log: (AnalyticsEvent, [String: Any]) -> Void = TrackingManager.logEvent) {
        for hit in LockedComplicationLog.hits(fromUserInfo: userInfo) {
            log(.watchComplicationLocked, hit.parameters)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Self.logEvents(fromUserInfo: userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let ids = SettingsStore().savedFavouriteStations
        DispatchQueue.main.async { self.sendFavourites(ids) }
    }

    /// The watch app was installed (or removed): send the list it missed.
    func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.isWatchAppInstalled else { return }
        let ids = SettingsStore().savedFavouriteStations
        DispatchQueue.main.async { self.sendFavourites(ids) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// After switching to another watch: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
