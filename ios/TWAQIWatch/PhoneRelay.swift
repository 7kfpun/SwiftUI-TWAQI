//
//  PhoneRelay.swift
//  TWAQIWatch
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import WatchConnectivity

/// Sends the complications' locked-style hits to the phone, which logs them
/// to Firebase (`LockedComplicationLog`). The watch has no Firebase, and the
/// widget extension can't reach the phone itself.
final class PhoneRelay: NSObject, WCSessionDelegate {
    static let shared = PhoneRelay()

    /// Activates the session; the queue is sent once it is active.
    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            flush()
        } else {
            session.activate()
        }
    }

    /// Hands the queued hits to WatchConnectivity, which delivers them even
    /// when the phone app isn't running. Without the phone app they stay
    /// queued rather than being dropped.
    func flush() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else { return }
        let hits = LockedComplicationLog.drain(from: WatchStore.sharedDefaults)
        guard !hits.isEmpty else { return }
        session.transferUserInfo(LockedComplicationLog.userInfo(for: hits))
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        flush()
    }
}
