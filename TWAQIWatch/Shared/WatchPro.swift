//
//  WatchPro.swift
//  TWAQIWatch
//
//  Created by kf on 21/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import StoreKit

/// Whether the reader owns the upgrade that unlocks the watch.
///
/// It is the same non-consumable that removes ads on iPhone. The phone records
/// its purchase in its own UserDefaults, which the watch can't see, so the
/// watch asks StoreKit instead: entitlements follow the Apple ID, whichever
/// device made the purchase.
enum WatchPro {
    static var productId: String? {
        getEnv("InAppPurchaseProductId")
    }

    /// Last known answer, shared with the complications through the app group
    /// so neither flashes the paywall while StoreKit is being asked again.
    static var isUnlocked: Bool {
        get { WatchStore.isProUnlocked }
        set { WatchStore.isProUnlocked = newValue }
    }

    /// Asks StoreKit and caches the answer.
    @discardableResult
    static func refresh() async -> Bool {
        guard let productId else { return false }

        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productId,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isUnlocked = owned
        return owned
    }
}
