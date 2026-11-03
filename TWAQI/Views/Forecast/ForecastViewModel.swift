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
        /// Rows came back, but none from today on: a saved copy older than
        /// the forecast it holds, while the refresh keeps failing.
        case noCurrentForecast
    }

    @Published private(set) var state: State = .loading

    /// The Watch app's one-shot locator, as in the welcome flow. Only used
    /// once location is allowed, so this tab never prompts.
    private let locator = Locator()
    /// Only read for its status: reading never prompts.
    private let statusManager = CLLocationManager()
    private var isLoadingForecasts = false
    private var isLoadingStations = false
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
    /// The list waits only on the forecast rows. The location fix (slow
    /// indoors) and the station list (a network request without a saved
    /// copy) each redraw it when they arrive: until then 北部 is first and
    /// favourites are named from their own saved readings.
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

        // Only needed to name the reader's or a favourite's area.
        if allowed || !favouriteStationIds.isEmpty, !isLoadingStations {
            isLoadingStations = true
            Task {
                let fetched = await Self.currentStations()
                isLoadingStations = false
                // A failed request keeps the list it had.
                if !fetched.isEmpty {
                    stations = fetched
                }
                render()
            }
        }

        guard !isLoadingForecasts else { return }
        isLoadingForecasts = true

        Task {
            let fetched = await Self.forecasts()
            isLoadingForecasts = false

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
        let next: State = areas.isEmpty ? .noCurrentForecast : .loaded(areas)
        if state != next {
            state = next
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
