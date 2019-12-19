//
//  SettingsStore.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import SwiftUI

let defaultCountry = Country(
    id: 0,
    code: "twn",
    lat: 12,
    lon: 123.1,
    zoom: 12,
    name: "Taiwan",
    nameLocal: "台灣"
)

let defaultStation = Station(
    id: 1,
    countryId: 1,
    countryCode: "twn",
    code: "Songshan",
    lat: 25.050000,
    lon: 121.578611,
    imageUrl: "",
    name: "Songshan",
    nameLocal: "松山"
)

let defaultHistoricalPollutant = HistoricalPollutant(
    aqi: 0,
    pm25: 0,
    pm10: 0,
    no2: 0,
    so2: 0,
    co: 0,
    o3: 0,
    windDirection: 0,
    windSpeed: 0,
    publishTime: "--"
)

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let airIndexTypeSelected = "airIndexTypeSelected"
        static let closestCountry = "closestCountry"
        static let closestCountryCode = "closestCountryCode"
        static let closestStationNew = "closestStationNew"
        static let closestStationName = "closestStationName"
        static let latestHistoricalPollutant = "latestHistoricalPollutant"
    }

    private let cancellable: Cancellable
    private let defaults: UserDefaults

    let objectWillChange = PassthroughSubject<Void, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Keys.airIndexTypeSelected: AirIndexTypes.aqi.rawValue,
            Keys.closestCountryCode: "twn",
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

    var closestCountry: Country {
        set { defaults.setStruct(newValue, forKey: Keys.closestCountry) }
        get { defaults.structData(Country.self, forKey: Keys.closestCountry) ?? defaultCountry }
    }

    var closestCountryCode: String {
        set { defaults.set(newValue, forKey: Keys.closestCountryCode) }
        get { defaults.string(forKey: Keys.closestCountryCode) ?? "twn" }
    }

    var closestStation: Station {
        set { defaults.setStruct(newValue, forKey: Keys.closestStationNew) }
        get { defaults.structData(Station.self, forKey: Keys.closestStationNew) ?? defaultStation }
    }

    var closestStationName: String {
        set { defaults.set(newValue, forKey: Keys.closestStationName) }
        get { defaults.string(forKey: Keys.closestStationName) ?? "松山" }
    }

    var latestHistoricalPollutant: HistoricalPollutant {
        set { defaults.setStruct(newValue, forKey: Keys.latestHistoricalPollutant) }
        get { defaults.structData(HistoricalPollutant.self, forKey: Keys.latestHistoricalPollutant) ?? defaultHistoricalPollutant }
    }
}
