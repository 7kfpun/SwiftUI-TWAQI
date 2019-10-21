//
//  SettingsStore.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let pro = "pro"
        static let airIndexTypeSelected = "airIndexTypeSelected"
        static let forecastEnabled = "forecastEnabled"
        static let dndEnabled = "dndEnabled"
        static let startDate = "startDate"
        static let endDate = "endDate"
    }

    private let cancellable: Cancellable
    private let defaults: UserDefaults

    let objectWillChange = PassthroughSubject<Void, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Keys.airIndexTypeSelected: Constants.AirIndexTypes.aqi.rawValue,
            Keys.forecastEnabled: true,
            Keys.dndEnabled: false,
            Keys.startDate: Date(),
            Keys.endDate: Date(),
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

    var airIndexTypeSelected: Constants.AirIndexTypes {
        get {
            return defaults.string(forKey: Keys.airIndexTypeSelected)
                .flatMap { Constants.AirIndexTypes(rawValue: $0) } ?? .aqi
        }

        set { defaults.set(newValue.rawValue, forKey: Keys.airIndexTypeSelected) }
    }

    var isForecastEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.forecastEnabled) }
        get { defaults.bool(forKey: Keys.forecastEnabled) }
    }

    var isDndEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.dndEnabled) }
        get { defaults.bool(forKey: Keys.dndEnabled) }
    }

    var startDate: Date {
        set { defaults.set(newValue, forKey: Keys.startDate) }
        get { defaults.value(forKey: Keys.startDate) as! Date }
    }

    var endDate: Date {
        set { defaults.set(newValue, forKey: Keys.endDate) }
        get { defaults.value(forKey: Keys.endDate) as! Date }
    }
}

extension SettingsStore {
    func unlockPro() {
        // TODO: in-app transactions here
        isPro = true
    }

    func restorePurchase() {
        // TODO: in-app purchase restore here
        isPro = true
    }
}