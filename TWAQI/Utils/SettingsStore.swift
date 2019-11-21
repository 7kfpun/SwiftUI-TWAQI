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
        static let closestStationName = "closestStationName"
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
            Keys.closestStationName: "松山",
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

    var closestStationName: String {
        set { defaults.set(newValue, forKey: Keys.closestStationName) }
        get { defaults.string(forKey: Keys.closestStationName) ?? "松山" }
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
