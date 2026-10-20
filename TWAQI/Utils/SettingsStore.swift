//
//  SettingsStore.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import StoreKit
import SwiftDate
import SwiftUI

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let pro = "pro"
        static let airIndexTypeSelected = "airIndexTypeSelected"
        static let dndEnabled = "dndEnabled"
        static let dndStartTime = "dndStartTime"
        static let dndEndTime = "dndEndTime"
        static let closestCountryCode = "closestCountryCode"
        static let supportedCountryCode = "supportedCountryCode"
        static let closestStationName = "closestStationName"
        static let lastestMapLat = "lastestMapLat"
        static let lastestMapLon = "lastestMapLon"
        static let lastestMapZoom = "lastestMapZoom"
        static let savedFavouriteStations = "savedFavouriteStations"
    }

    private let cancellable: Cancellable
    private let defaults: UserDefaults

    let objectWillChange = PassthroughSubject<Void, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Keys.airIndexTypeSelected: AirIndexTypes.aqi.rawValue,
            Keys.dndEnabled: false,
            Keys.dndStartTime: Date(),
            Keys.dndEndTime: Date() + 2.hours,
            Keys.closestCountryCode: "twn",
            Keys.closestStationName: "松山",
            Keys.lastestMapLat: MapHome.latitude,
            Keys.lastestMapLon: MapHome.longitude,
            Keys.lastestMapZoom: MapHome.zoom,
            Keys.savedFavouriteStations: [126],
        ])

        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .map { _ in () }
            // This notification fires for *any* write to the shared defaults, and
            // the ad/analytics/push SDKs write constantly — sometimes from inside
            // a SwiftUI view update, which made `objectWillChange` fire mid-update.
            // Delivering on the next run-loop pass moves the send out of the
            // current update and coalesces the storm into a single refresh.
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .subscribe(objectWillChange)
    }

    var isPro: Bool {
        set { defaults.set(newValue, forKey: Keys.pro) }
        get { defaults.bool(forKey: Keys.pro) }
    }

    var airIndexTypeSelected: AirIndexTypes {
        set {
            defaults.set(newValue.rawValue, forKey: Keys.airIndexTypeSelected)
            TrackingManager.logEvent(eventName: "select_index", parameters: ["label": newValue.rawValue])
        }
        get {
            return defaults.string(forKey: Keys.airIndexTypeSelected)
                .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi
        }
    }

    var isDndEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.dndEnabled) }
        get { defaults.bool(forKey: Keys.dndEnabled) }
    }

    var dndStartTime: Date {
        set { defaults.set(newValue, forKey: Keys.dndStartTime) }
        // `as?`, not `as!`. `register(defaults:)` writes to the *registration*
        // domain, which is volatile — it exists only after a SettingsStore has
        // been constructed in this process. A read that beats construction, or
        // a value an older build stored as a different type, used to trap.
        get { defaults.object(forKey: Keys.dndStartTime) as? Date ?? Date() }
    }

    var dndEndTime: Date {
        set { defaults.set(newValue, forKey: Keys.dndEndTime) }
        get { defaults.object(forKey: Keys.dndEndTime) as? Date ?? Date() + 2.hours }
    }

    /// Country whose data the app fully supports, resolved from the countries
    /// endpoint by `Country.supportedId`. Empty until the map has loaded once.
    var supportedCountryCode: String {
        set { defaults.set(newValue, forKey: Keys.supportedCountryCode) }
        get { defaults.string(forKey: Keys.supportedCountryCode) ?? "" }
    }

    var closestCountryCode: String {
        set { defaults.set(newValue, forKey: Keys.closestCountryCode) }
        get { defaults.string(forKey: Keys.closestCountryCode) ?? "twn" }
    }

    var closestStationName: String {
        set { defaults.set(newValue, forKey: Keys.closestStationName) }
        get { defaults.string(forKey: Keys.closestStationName) ?? "松山" }
    }

    var lastestMapLat: Double {
        set { defaults.set(newValue, forKey: Keys.lastestMapLat) }
        get { defaults.double(forKey: Keys.lastestMapLat) }
    }

    var lastestMapLon: Double {
        set { defaults.set(newValue, forKey: Keys.lastestMapLon) }
        get { defaults.double(forKey: Keys.lastestMapLon) }
    }

    var lastestMapZoom: Float {
        set { defaults.set(newValue, forKey: Keys.lastestMapZoom) }
        get { defaults.float(forKey: Keys.lastestMapZoom) }
    }

    var savedFavouriteStations: [Int] {
        set { defaults.set(newValue, forKey: Keys.savedFavouriteStations) }
        // A stored array containing anything other than Int — from an older
        // build, or a partially written value — used to trap the whole app.
        get { defaults.array(forKey: Keys.savedFavouriteStations) as? [Int] ?? [] }
    }
}

extension SettingsStore {
    /// Re-reads Pro from StoreKit into the flag the ad code reads.
    ///
    /// The flag used to be set once on purchase and never cleared. With
    /// subscriptions it has to follow StoreKit: a lapsed or refunded
    /// subscription turns ads back on.
    static func refreshPro() async {
        let entitled = await IAPManager.isEntitled()
        await MainActor.run {
            UserDefaults.standard.set(entitled, forKey: Keys.pro)
        }
    }

    /// Purchases completed outside the Pro screen: renewals, refunds, Ask to
    /// Buy approvals, a purchase made on another device. Started once at launch.
    static func observeProTransactions() {
        Task.detached {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await refreshPro()
            }
        }
    }
}
