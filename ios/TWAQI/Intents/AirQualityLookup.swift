//
//  AirQualityLookup.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation

/// Finds the reading a Siri / Shortcuts question is about (FOX-74), through
/// the widget's data path: `WatchAPI` for the fetch, the app group
/// (`WatchStore`) for the last saved readings when offline.
enum AirQualityLookup {
    struct Result {
        let reading: WatchReading?
        let freshness: AirQualityAnswer.Freshness
        let note: StationFallbackNote?
        /// For analytics: nearest, favourite, station, default.
        let kind: String
    }

    /// `requestedStationId` nil means "nearest". Never asks for location:
    /// with no permission it answers for the first favourite and says so.
    @MainActor
    static func lookup(requestedStationId: Int?) async -> Result {
        let favouriteIds = WatchStore.favouriteStationIds
        let location = knownLocation()
        // The map's last closest station stands in for a fix the system
        // doesn't have to hand, as long as location is allowed.
        let home = WatchStore.homeReading
        let resolution = StationResolution.resolve(
            requestedStationId: requestedStationId,
            favouriteIds: favouriteIds,
            locationAvailable: locationAllowed && (location != nil || home != nil)
        )

        switch resolution.plan {
        case .station(let id):
            let kind = requestedStationId == nil ? "favourite" : "station"
            if let pollutant = try? await WatchAPI.currentPollutant(stationId: id) {
                cacheFavourites([pollutant])
                return Result(reading: WatchReading(pollutant), freshness: .live, note: resolution.note, kind: kind)
            }
            return Result(reading: WatchStore.newestCachedReading(stationId: id), freshness: .cached, note: resolution.note, kind: kind)

        case .nearest:
            if let location, let all = try? await WatchAPI.currentPollutants(),
               let closest = WatchAPI.closest(to: location, in: all) {
                cacheFavourites(all)
                return Result(reading: WatchReading(closest), freshness: .live, note: nil, kind: "nearest")
            }
            if location == nil, let home,
               let pollutant = try? await WatchAPI.currentPollutant(stationId: home.stationId) {
                return Result(reading: WatchReading(pollutant), freshness: .live, note: nil, kind: "nearest")
            }
            return Result(reading: home, freshness: .cached, note: nil, kind: "nearest")

        case .defaultLocation:
            if let all = try? await WatchAPI.currentPollutants(),
               let closest = WatchAPI.closest(to: WatchAPI.defaultLocation, in: all) {
                return Result(reading: WatchReading(closest), freshness: .live, note: resolution.note, kind: "default")
            }
            return Result(
                reading: WatchStore.latestReading ?? home, freshness: .cached, note: resolution.note, kind: "default"
            )
        }
    }

    /// Whether the reader already gave the app location; never prompts.
    @MainActor
    private static var locationAllowed: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    /// The last fix the system holds for the app, without starting updates.
    @MainActor
    private static func knownLocation() -> CLLocation? {
        guard locationAllowed else { return nil }
        return CLLocationManager().location
    }

    /// Keeps the widget's favourite cache current with anything fetched here.
    private static func cacheFavourites(_ pollutants: Pollutants) {
        let ids = Set(WatchStore.favouriteStationIds)
        WatchStore.cacheFavouriteReadings(pollutants.filter { ids.contains($0.stationId) }.map(WatchReading.init))
    }
}
