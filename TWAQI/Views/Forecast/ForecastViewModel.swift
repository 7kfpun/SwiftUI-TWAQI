//
//  ForecastViewModel.swift
//  TWAQI
//
//  Created by kf on 3/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation

/// The Forecast tab (FOX-32): every 空品區's forecast from `AqiForecastStore`,
/// the reader's area first, then the favourites' areas, then the rest
/// (`ForecastTabOrdering`).
@MainActor
final class ForecastViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([ForecastTabArea])
        /// Nothing fetched and nothing cached: offline on first use, or
        /// Directus not reachable.
        case empty
    }

    @Published private(set) var state: State = .loading

    /// The Watch app's one-shot locator, as in the welcome flow. Only used
    /// once location is allowed, so this tab never prompts.
    private let locator = Locator()
    /// Only read for its status: reading never prompts.
    private let statusManager = CLLocationManager()
    private var isLoading = false
    private var isLocating = false

    /// What the list is built from, kept so each piece can redraw it as it
    /// arrives: the forecast rows, the country station list (to name each
    /// station's area), the latest favourites and the reader's location.
    private var rows: [AqiForecast]?
    private var stations: Pollutants = []
    private var favouriteStationIds: [Int] = []
    private var location: CLLocation?

    /// Loads, or reloads on each visit: the store answers from memory inside
    /// its TTL, and favourites may have changed since.
    ///
    /// The list doesn't wait on a location fix, which can take a while
    /// indoors: it shows with 北部 first and moves the reader's area up
    /// once the fix arrives.
    func load(favouriteStationIds: [Int]) {
        self.favouriteStationIds = favouriteStationIds
        // Favourites edited since the last visit re-pin at once; a load
        // already running picks up the new ones when it finishes.
        render()

        let allowed = isLocationAllowed
        if allowed, location == nil, !isLocating {
            isLocating = true
            Task {
                location = await locator.current()
                isLocating = false
                render()
            }
        }

        guard !isLoading else { return }
        isLoading = true

        Task {
            async let forecasts = Self.forecasts()
            // Only needed to name the reader's or a favourite's area.
            if allowed || !favouriteStationIds.isEmpty {
                stations = await Self.currentStations()
            }
            let fetched = await forecasts
            isLoading = false

            // A reload that finds nothing keeps the last rows it had.
            if !fetched.isEmpty || rows == nil {
                rows = fetched
            }
            render()
        }
    }

    private func render() {
        guard let rows = rows else { return }
        guard !rows.isEmpty else {
            if case .loaded = state { return }
            state = .empty
            return
        }

        let today = AqiForecastDates.today()
        let areaNames = Array(Set(rows.filter { $0.forecastDate >= today }.map(\.area))).sorted()
        let areaOf = { (pollutant: Pollutant) in
            AqiForecastMatcher.area(areaLocal: pollutant.areaLocal, countyLocal: pollutant.countyLocal, in: areaNames)
        }
        let nearest = location.flatMap { WatchAPI.closest(to: $0, in: stations) }

        let areas = ForecastTabOrdering.areas(
            forecasts: rows,
            readerArea: nearest.flatMap(areaOf),
            favouriteAreas: favourites().map(areaOf),
            today: today,
            chinese: Locale.isChinese
        )
        if state != .loaded(areas) {
            state = .loaded(areas)
        }
    }

    private static func forecasts() async -> [AqiForecast] {
        await withCheckedContinuation { continuation in
            AqiForecastStore.shared.forecasts { continuation.resume(returning: $0) }
        }
    }

    /// The favourite stations, in favourites order, as far as they are known.
    private func favourites() -> [Pollutant] {
        let byId = Dictionary(stations.map { ($0.stationId, $0) }, uniquingKeysWith: { first, _ in first })
        // A favourite missing from the country list (not reporting now) may
        // still have a saved reading of its own, which carries its area.
        let missing = favouriteStationIds.filter { byId[$0] == nil }
        let saved = missing.isEmpty ? [:] : Dictionary(
            PollutantCache.shared.pollutants(stationIds: missing).map { ($0.stationId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return favouriteStationIds.compactMap { byId[$0] ?? saved[$0] }
    }

    private var isLocationAllowed: Bool {
        switch statusManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    /// The country list, saved copy first: it only has to name each
    /// station's area, which doesn't change between readings.
    private static func currentStations() async -> Pollutants {
        if let saved = PollutantCache.shared.pollutants(countryCode: WatchStore.countryCode) {
            return saved
        }
        return await withCheckedContinuation { continuation in
            APIManager.getCurrentPollutants(countryCode: WatchStore.countryCode) { result in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }
    }
}
