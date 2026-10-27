//
//  Favourites.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import Observation

/// Saved stations, in the order they were added.
///
/// Same key and default as the iOS `SettingsStore`, so the list behaves the
/// same; it isn't shared between devices (each app has its own defaults).
@MainActor
@Observable
final class Favourites {
    private static let key = "savedFavouriteStations"
    /// 松山, as on iOS.
    private static let initial = [126]

    private let defaults: UserDefaults

    private(set) var stationIds: [Int] {
        didSet { defaults.set(stationIds, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Tolerates anything other than [Int] left by an older build, like iOS.
        stationIds = defaults.object(forKey: Self.key) == nil
            ? Self.initial
            : defaults.array(forKey: Self.key) as? [Int] ?? []
    }

    func contains(_ stationId: Int) -> Bool {
        stationIds.contains(stationId)
    }

    func add(_ stationId: Int) {
        guard !contains(stationId) else { return }
        stationIds.append(stationId)
    }

    func toggle(_ stationId: Int) {
        if contains(stationId) {
            remove(stationId)
        } else {
            add(stationId)
        }
    }

    func remove(_ stationId: Int) {
        stationIds.removeAll { $0 == stationId }
    }

    func remove(atOffsets offsets: IndexSet) {
        stationIds.remove(atOffsets: offsets)
    }

    func removeAll() {
        stationIds = []
    }
}
