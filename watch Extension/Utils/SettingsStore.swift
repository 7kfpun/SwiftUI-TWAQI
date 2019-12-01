//
//  SettingsStore.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import SwiftUI

let defaultStation = Station(
    name: "Matsu",
    nameLocal: "馬祖",
    lat: 26.160469,
    lon: 119.949875,
    imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
)

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let airIndexTypeSelected = "airIndexTypeSelected"
        static let closestStation = "closestStation"
        static let closestStationName = "closestStationName"
    }

    private let cancellable: Cancellable
    private let defaults: UserDefaults

    let objectWillChange = PassthroughSubject<Void, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Keys.airIndexTypeSelected: AirIndexTypes.aqi.rawValue,
            Keys.closestStationName: "松山",
        ])

        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .map { _ in () }
            .subscribe(objectWillChange)
    }

    var airIndexTypeSelected: AirIndexTypes {
        set { defaults.set(newValue.rawValue, forKey: Keys.airIndexTypeSelected) }
        get {
            return defaults.string(forKey: Keys.airIndexTypeSelected)
                .flatMap { AirIndexTypes(rawValue: $0) } ?? .aqi
        }
    }

    var closestStation: Station {
        set { defaults.setStruct(newValue, forKey: Keys.closestStation) }
        get { defaults.structData(Station.self, forKey: Keys.closestStation) ?? defaultStation }
    }

    var closestStationName: String {
        set { defaults.set(newValue, forKey: Keys.closestStationName) }
        get { defaults.string(forKey: Keys.closestStationName) ?? "松山" }
    }
}
