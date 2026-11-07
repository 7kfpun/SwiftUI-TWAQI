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

// MARK: - Widget station picker (FOX-137)

extension StationDirectoryEntry {
    init(_ pollutant: Pollutant) {
        self.init(id: pollutant.stationId, name: pollutant.name, nameLocal: pollutant.nameLocal, code: pollutant.code)
    }

    /// The station's name in `locale`'s language, never blank.
    func displayName(locale: Locale) -> String {
        let preferred = locale.isChinese ? nameLocal : name
        if !preferred.isEmpty { return preferred }
        return code.isEmpty ? "#\(id)" : code
    }

    /// Whether `query` finds the station by name (either language) or code.
    /// Case, accents and 臺/台 are ignored; a blank query finds every station.
    func matches(_ query: String) -> Bool {
        let needle = Self.normalized(query)
        guard !needle.isEmpty else { return true }
        return [name, nameLocal, code].contains { Self.normalized($0).contains(needle) }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "臺", with: "台")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Stations matching `query`, the reader's favourites first (in their
    /// order), then the rest in the API's order.
    static func search(_ query: String, in all: [StationDirectoryEntry], favouriteIds: [Int]) -> [StationDirectoryEntry] {
        let found = all.filter { $0.matches(query) }
        let rank = Dictionary(favouriteIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let favourites = found.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        return favourites + found.filter { rank[$0.id] == nil }
    }
}

/// How a widget picks the station it leads with.
enum WidgetStationMode: String, Equatable {
    case closest, firstFavourite, station
}

/// Which station a widget leads with, apart from App Intents and the
/// network, so the choice can be tested.
enum WidgetStationChoice {
    /// The station id a widget leads with. Nil means the closest station: the
    /// mode says so, or it asks for a favourite or a chosen station that
    /// isn't there (no favourite saved, no station picked yet).
    static func leadingId(mode: WidgetStationMode, chosenId: Int?, firstFavouriteId: Int?) -> Int? {
        switch mode {
        case .closest: return nil
        case .firstFavourite: return firstFavouriteId
        case .station: return chosenId
        }
    }

    /// A chosen station that disappeared: the request went through but the
    /// station isn't in the answer. A failed request (offline) is not
    /// "gone"; the widget keeps the last reading it saved.
    static func isGone(chosenId: Int, fetchedIds: [Int], fetchSucceeded: Bool) -> Bool {
        fetchSucceeded && !fetchedIds.contains(chosenId)
    }

    /// The station part of a widget's page-state key, so two widgets of the
    /// same size set to different stations don't share it.
    static func keyPart(mode: WidgetStationMode, chosenId: Int?) -> String {
        mode == .station ? "station-\(chosenId.map(String.init) ?? "none")" : mode.rawValue
    }
}

/// A station picked for the Home Screen widget, any of the country's
/// stations (unlike `StationEntity`, which lists the favourites only).
@available(iOS 16.0, *)
struct ChosenStationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Intent.station"
    static var defaultQuery = ChosenStationQuery()

    let id: String
    let name: String

    init(_ entry: StationDirectoryEntry) {
        id = String(entry.id)
        name = entry.displayName(locale: .app)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    var stationId: Int? { Int(id) }
}

@available(iOS 16.0, *)
struct ChosenStationQuery: EntityStringQuery {
    /// Every station, fresh when the network answers, else the last list
    /// saved in the app group.
    private func directory() async -> [StationDirectoryEntry] {
        if let fetched = try? await WatchAPI.currentPollutants(), !fetched.isEmpty {
            let entries = fetched.map(StationDirectoryEntry.init)
            WatchStore.stationDirectory = entries
            return entries
        }
        return WatchStore.stationDirectory
    }

    func entities(for identifiers: [ChosenStationEntity.ID]) async throws -> [ChosenStationEntity] {
        let all = await directory()
        return identifiers.compactMap { id in
            guard let stationId = Int(id) else { return nil }
            // A station missing from the list still resolves, by id: the
            // widget notices it is gone and falls back to the closest.
            return all.first { $0.id == stationId }.map(ChosenStationEntity.init)
                ?? ChosenStationEntity(StationDirectoryEntry(id: stationId, name: "#\(stationId)", nameLocal: "#\(stationId)", code: ""))
        }
    }

    func entities(matching string: String) async throws -> [ChosenStationEntity] {
        StationDirectoryEntry.search(string, in: await directory(), favouriteIds: WatchStore.favouriteStationIds)
            .map(ChosenStationEntity.init)
    }

    func suggestedEntities() async throws -> [ChosenStationEntity] {
        StationDirectoryEntry.search("", in: await directory(), favouriteIds: WatchStore.favouriteStationIds)
            .map(ChosenStationEntity.init)
    }
}
