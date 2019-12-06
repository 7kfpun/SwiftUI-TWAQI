//
//  SettingsStore.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import SwiftDate
import SwiftUI

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let pro = "pro"
        static let airIndexTypeSelected = "airIndexTypeSelected"
        static let forecastEnabled = "forecastEnabled"
        static let dndEnabled = "dndEnabled"
        static let dndStartTime = "dndStartTime"
        static let dndEndTime = "dndEndTime"
        static let closestCountryCode = "closestCountryCode"
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
            Keys.forecastEnabled: false,
            Keys.dndEnabled: false,
            Keys.dndStartTime: Date(),
            Keys.dndEndTime: Date() + 2.hours,
            Keys.closestCountryCode: "twn",
            Keys.closestStationName: "松山",
            Keys.lastestMapLat: 23.49,
            Keys.lastestMapLon: 120.96,
            Keys.lastestMapZoom: 7.9,
            Keys.savedFavouriteStations: [126],
        ])

        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .map { _ in () }
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

    var isForecastEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.forecastEnabled) }
        get { defaults.bool(forKey: Keys.forecastEnabled) }
    }

    var isDndEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.dndEnabled) }
        get { defaults.bool(forKey: Keys.dndEnabled) }
    }

    var dndStartTime: Date {
        set { defaults.set(newValue, forKey: Keys.dndStartTime) }
        get { defaults.object(forKey: Keys.dndStartTime) as! Date }
    }

    var dndEndTime: Date {
        set { defaults.set(newValue, forKey: Keys.dndEndTime) }
        get { defaults.object(forKey: Keys.dndEndTime) as! Date }
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
        get { defaults.array(forKey: Keys.savedFavouriteStations) as! [Int] }
    }
}

extension SettingsStore {
    func unlockPro() {
        TrackingManager.logEvent(eventName: "user_premium_buy_product_started")
        IAPManager.shared.purchaseMyProduct(index: 0)
        IAPManager.shared.purchaseStatusBlock = { type in
            if type == .purchased {
                print("Purchased")
                self.isPro = true
                TrackingManager.logEvent(eventName: "user_premium_buy_product_done")
            } else {
                print(type)
                TrackingManager.logEvent(eventName: "user_premium_buy_product_failed")
            }
        }
    }

    func restorePurchase() {
        TrackingManager.logEvent(eventName: "user_premium_restore_purchase_started")
        IAPManager.shared.restorePurchase()
        IAPManager.shared.purchaseStatusBlock = { type in
            if type == .restored {
                print("Restored")
                self.isPro = true
                TrackingManager.logEvent(eventName: "user_premium_restore_purchase_done")
            } else {
                print(type)
                TrackingManager.logEvent(eventName: "user_premium_restore_purchase_failed")
            }
        }
    }
}
