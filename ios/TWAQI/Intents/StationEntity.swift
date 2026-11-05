//
//  StationEntity.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import Foundation

/// A station Siri, Shortcuts and the Control Center control can be asked
/// about: "Nearest", or one of the reader's favourites (FOX-74).
///
/// Built in both the app and the widget extension from the app group
/// (`WatchStore.favouriteStationIds`, `favouriteReadings`), the same data the
/// Home Screen widget lists, so both list the favourites in the same order.
@available(iOS 16.0, *)
struct StationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Intent.station"
    static var defaultQuery = StationEntityQuery()

    let id: String
    let name: String

    init(_ choice: StationChoice) {
        id = choice.id
        name = choice.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    /// Nil for "Nearest".
    var stationId: Int? { Int(id) }

    static var nearest: StationEntity {
        StationEntity(.nearest(bundle: .appLanguage))
    }

    /// "Nearest", then the favourites in the reader's order. Names come from
    /// the cached readings, in the app's language.
    static var all: [StationEntity] {
        StationChoice.choices(
            favouriteIds: WatchStore.favouriteStationIds,
            readings: WatchStore.favouriteReadings,
            locale: .app,
            bundle: .appLanguage
        ).map(StationEntity.init)
    }
}

@available(iOS 16.0, *)
struct StationEntityQuery: EntityQuery {
    func entities(for identifiers: [StationEntity.ID]) async throws -> [StationEntity] {
        let all = StationEntity.all
        // A station chosen earlier and since removed from Favourites still
        // resolves, by id: its reading is fetched by id either way.
        return identifiers.map { id in
            all.first { $0.id == id } ?? StationEntity(StationChoice(id: id, name: "#\(id)"))
        }
    }

    func suggestedEntities() async throws -> [StationEntity] {
        StationEntity.all
    }

    func defaultResult() async -> StationEntity? {
        .nearest
    }
}

extension WatchStore {
    /// The newest reading saved in the app group for `stationId`: a
    /// favourite's, or the closest station's. What Siri and the control fall
    /// back to offline.
    static func newestCachedReading(stationId: Int) -> WatchReading? {
        (favouriteReadings + [latestReading, homeReading].compactMap { $0 })
            .filter { $0.stationId == stationId }
            .max { $0.publishTime < $1.publishTime }
    }
}
