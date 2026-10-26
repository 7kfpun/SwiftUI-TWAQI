//
//  StationStore.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation
import Observation

/// Every station's latest reading, shared by the volume and the immersive
/// tabletop so both show the same selection.
@MainActor
@Observable
final class StationStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    private(set) var stations: Pollutants = []
    private(set) var loadState = LoadState.idle
    private(set) var lastRefreshed: Date?
    var index = AirIndexTypes.aqi
    var selectedStationId: Int?
    /// Pins become arrows showing where each station's air is heading, like
    /// the iOS map's wind mode.
    var isWindMode = false
    /// While the tabletop is out, the volume's island hides so there aren't
    /// two maps in the room; its controls stay.
    var isTabletopOpen = false

    /// The reader's rough position, once they've allowed it.
    private(set) var userLocation: CLLocation?
    private(set) var isLocating = false
    private let locator = Locator()

    var nearestStation: Pollutant? {
        userLocation.flatMap { WatchAPI.closest(to: $0, in: stations) }
    }

    /// The API republishes hourly; this keeps a long session current without
    /// hammering it.
    private static let refreshInterval: Duration = .seconds(10 * 60)

    var selectedStation: Pollutant? {
        selectedStationId.flatMap(station)
    }

    func station(_ id: Int) -> Pollutant? {
        stations.first { $0.stationId == id }
    }

    /// Finds the reader and selects the station nearest them, like the iOS
    /// map's my-location button.
    func selectNearest() async {
        isLocating = true
        defer { isLocating = false }
        if let location = await locator.current() {
            userLocation = location
        }
        selectedStationId = nearestStation?.stationId
    }

    /// Most recent `publish_time` across stations, for the "as of" line.
    var latestPublishTime: String? {
        stations.map(\.publishTime).max()
    }

    func refresh() async {
        loadState = .loading
        do {
            // The API includes stations without coordinates; they can't be placed.
            stations = try await WatchAPI.currentPollutants().filter { $0.lat != 0 && $0.lon != 0 }
            lastRefreshed = Date()
            loadState = .idle
            if let id = selectedStationId, !stations.contains(where: { $0.stationId == id }) {
                selectedStationId = nil
            }
        } catch {
            // Keep showing the last good readings; only the status line changes.
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Refreshes now and then periodically until the calling task is cancelled.
    func keepFresh() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}
