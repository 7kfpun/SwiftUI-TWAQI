//
//  IAPManager.swift
//  TWAQI
//
//  Created by kf on 5/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import StoreKit

/// What counts as Pro, shared by the phone, the watch and its complications.
///
/// Pro is either the original one-time ad-free purchase, which existing buyers
/// keep for life, or an active subscription. Both are read from StoreKit rather
/// than a stored flag, so a subscription that lapses or is refunded turns Pro
/// off, and a purchase on one device counts on the others.
enum IAPManager {
    /// The original non-consumable, still sold as the lifetime option.
    static var lifetimeProductId: String? {
        getEnv("InAppPurchaseProductId")
    }

    /// Subscription group 22497426, highest level of service last as App Store
    /// Connect orders it.
    static let subscriptionProductIds = [
        "com.kfpun.twaqi.subscription.adfree.1m",
        "com.kfpun.twaqi.subscription.adfree.6m",
        "com.kfpun.twaqi.subscription.adfree.12m",
    ]

    static var productIds: [String] {
        subscriptionProductIds + [lifetimeProductId].compactMap { $0 }
    }

    /// Products in display order: subscriptions shortest first, then lifetime.
    static func products() async throws -> [Product] {
        let ids = productIds
        let products = try await Product.products(for: ids)
        return products.sorted {
            (ids.firstIndex(of: $0.id) ?? .max) < (ids.firstIndex(of: $1.id) ?? .max)
        }
    }

    /// `currentEntitlements` already drops expired subscriptions; the revocation
    /// check covers refunds.
    static func isEntitled() async -> Bool {
        if let forced = proOverride.forcedValue, await isTestEnvironment() {
            return forced
        }

        let ids = Set(productIds)
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               ids.contains(transaction.productID),
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    // MARK: - Developer override

    /// Forces Pro on or off for testing, from the hidden developer section.
    enum ProOverride: String, CaseIterable {
        case appStore
        case forcePro
        case forceFree

        var forcedValue: Bool? {
            switch self {
            case .appStore: return nil
            case .forcePro: return true
            case .forceFree: return false
            }
        }
    }

    /// Kept in the app group so the watch's complications see the watch app's
    /// choice. Each device has its own: the phone's doesn't reach the watch.
    private static var overrideDefaults: UserDefaults {
        UserDefaults(suiteName: "group.com.kfpun.twaqi") ?? .standard
    }

    static var proOverride: ProOverride {
        get {
            overrideDefaults.string(forKey: "proOverride").flatMap(ProOverride.init) ?? .appStore
        }
        set { overrideDefaults.set(newValue.rawValue, forKey: "proOverride") }
    }

    /// Debug, TestFlight and sandbox builds. The override is ignored anywhere
    /// else, so a customer who finds the hidden section can't unlock Pro.
    static func isTestEnvironment() async -> Bool {
        #if DEBUG
        return true
        #else
        if #available(iOS 16.0, watchOS 9.0, *),
           case .verified(let transaction)? = try? await AppTransaction.shared {
            return transaction.environment != .production
        }
        // AppTransaction can fail offline or on the watch; the receipt's name
        // still tells TestFlight and sandbox apart from the App Store.
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    enum PurchaseOutcome {
        case purchased
        /// Cancelled, or waiting on Ask to Buy; `Transaction.updates` delivers
        /// the approval later.
        case notCompleted
    }

    static func purchase(_ product: Product) async throws -> PurchaseOutcome {
        guard case .success(let verification) = try await product.purchase(),
              case .verified(let transaction) = verification
        else { return .notCompleted }

        await transaction.finish()
        return .purchased
    }
}
