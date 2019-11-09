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
        get {
            return defaults.string(forKey: Keys.airIndexTypeSelected)
                .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi
        }

        set { defaults.set(newValue.rawValue, forKey: Keys.airIndexTypeSelected) }
    }

    var isForecastEnabled: Bool {
        set {
            defaults.set(newValue, forKey: Keys.forecastEnabled)
            if newValue {
                OneSignalManager.enableForecast { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            } else {
                OneSignalManager.disableForecast { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }
        }
        get { defaults.bool(forKey: Keys.forecastEnabled) }
    }

    var isDndEnabled: Bool {
        set {
            defaults.set(newValue, forKey: Keys.dndEnabled)
            if newValue {
                defaults.set(Date(), forKey: Keys.dndStartTime)
                defaults.set(Date() + 2.hours, forKey: Keys.dndEndTime)

                OneSignalManager.enableDnd(dndStartTime: Date(), dndEndTime: Date() + 2.hours) { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            } else {
                OneSignalManager.disableDnd { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }
        }
        get { defaults.bool(forKey: Keys.dndEnabled) }
    }

    var dndStartTime: Date {
        set {
            defaults.set(newValue, forKey: Keys.dndStartTime)
            OneSignalManager.enableDnd(dndStartTime: dndStartTime, dndEndTime: dndEndTime) { result in
                switch result {
                case .success(let result):
                    print(result)
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
        get { defaults.object(forKey: Keys.dndStartTime) as! Date }
    }

    var dndEndTime: Date {
        set {
            defaults.set(newValue, forKey: Keys.dndEndTime)
            OneSignalManager.enableDnd(dndStartTime: dndStartTime, dndEndTime: dndEndTime) { result in
                switch result {
                case .success(let result):
                    print(result)
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
        get { defaults.object(forKey: Keys.dndEndTime) as! Date }
    }
}

extension SettingsStore {
    func unlockPro() {
        IAPManager.shared.purchaseMyProduct(index: 0)
        IAPManager.shared.purchaseStatusBlock = { type in
            if type == .purchased {
                print("Purchased")
                self.isPro = true
            } else {
                print(type)
            }
        }
    }

    func restorePurchase() {
        IAPManager.shared.restorePurchase()
        IAPManager.shared.purchaseStatusBlock = { type in
            if type == .restored {
                print("Restored")
                self.isPro = true
            } else {
                print(type)
            }
        }
    }
}
