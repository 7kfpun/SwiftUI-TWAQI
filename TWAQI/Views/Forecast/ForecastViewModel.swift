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

    /// Loads, or reloads on each visit: the store answers from memory inside
    /// its TTL, and favourites may have changed since.
    func load(favouriteStationIds: [Int]) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            async let forecasts = Self.forecasts()
            async let stations = stationsForAreas(favouriteStationIds: favouriteStationIds)
            let (rows, known) = await (forecasts, stations)
            isLoading = false

            guard !rows.isEmpty else {
                // A reload that finds nothing keeps what is already shown.
                if case .loaded = state { return }
                state = .empty
                return
            }

            let today = AqiForecastDates.today()
            let areaNames = Array(Set(rows.filter { $0.forecastDate >= today }.map(\.area))).sorted()
            let areaOf = { (pollutant: Pollutant) in
                AqiForecastMatcher.area(areaLocal: pollutant.areaLocal, countyLocal: pollutant.countyLocal, in: areaNames)
            }

            state = .loaded(ForecastTabOrdering.areas(
                forecasts: rows,
                readerArea: known.nearest.flatMap(areaOf),
                favouriteAreas: known.favourites.map(areaOf),
                today: today,
                chinese: Locale.isChinese
            ))
        }
    }

    private static func forecasts() async -> [AqiForecast] {
        await withCheckedContinuation { continuation in
            AqiForecastStore.shared.forecasts { continuation.resume(returning: $0) }
        }
    }

    /// The station nearest the reader (nil without location) and the
    /// favourite stations, in favourites order, as far as they are known.
    private func stationsForAreas(favouriteStationIds: [Int]) async -> (nearest: Pollutant?, favourites: [Pollutant]) {
        let location = await currentLocation()
        guard location != nil || !favouriteStationIds.isEmpty else { return (nil, []) }

        let stations = await Self.currentStations()
        let nearest = location.flatMap { WatchAPI.closest(to: $0, in: stations) }

        let byId = Dictionary(stations.map { ($0.stationId, $0) }, uniquingKeysWith: { first, _ in first })
        // A favourite missing from the country list (not reporting now) may
        // still have a saved reading of its own, which carries its area.
        let missing = favouriteStationIds.filter { byId[$0] == nil }
        let saved = missing.isEmpty ? [:] : Dictionary(
            PollutantCache.shared.pollutants(stationIds: missing).map { ($0.stationId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let favourites = favouriteStationIds.compactMap { byId[$0] ?? saved[$0] }
        return (nearest, favourites)
    }

    private func currentLocation() async -> CLLocation? {
        switch statusManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return await locator.current()
        default:
            return nil
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
