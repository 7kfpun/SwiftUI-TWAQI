//
//  WatchPro.swift
//  TWAQIWatch
//
//  Created by kf on 21/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Whether the reader has Pro, which unlocks the watch.
///
/// The rule lives in `IAPManager`, shared with the phone: the original one-time
/// purchase or an active subscription. StoreKit entitlements follow the Apple
/// ID, so a purchase on the phone counts here too.
enum WatchPro {
    /// Last known answer, shared with the complications through the app group
    /// so neither flashes the paywall while StoreKit is being asked again.
    static var isUnlocked: Bool {
        get { WatchStore.isProUnlocked }
        set { WatchStore.isProUnlocked = newValue }
    }

    /// Asks StoreKit and caches the answer.
    @discardableResult
    static func refresh() async -> Bool {
        let entitled = await IAPManager.isEntitled()
        isUnlocked = entitled
        return entitled
    }
}
