//
//  WidgetPaging.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// What a Home Screen widget's buttons changed (FOX-76): the station a
/// medium or large widget pages to with ‹ ›, and the index its label was
/// tapped to. Kept per widget in the app group, keyed by
/// `WidgetPaging.key(family:station:index:)`.
struct WidgetPageState: Codable, Equatable {
    /// The station paged to. Nil is the default page: the widget's station.
    var stationId: Int?
    /// `AirIndexTypes` raw value the label was cycled to. Nil is the index
    /// chosen in the edit sheet.
    var index: String?
    /// The last tap on a button, for the 30-minute reset and to tell the
    /// reload a tap asks for from a scheduled one.
    var tappedAt: Date?
    /// The last timeline that fetched readings.
    var refreshedAt: Date?

    init(stationId: Int? = nil, index: String? = nil, tappedAt: Date? = nil, refreshedAt: Date? = nil) {
        self.stationId = stationId
        self.index = index
        self.tappedAt = tappedAt
        self.refreshedAt = refreshedAt
    }
}

/// Paging through favourites and cycling the index on the Home Screen widget
/// (FOX-76). Pure, so the rules are tested in the app's tests; the widget's
/// intents and timeline provider apply them.
enum WidgetPaging {
    /// A paged widget goes back to its own station after this long without
    /// a tap.
    static let resetInterval: TimeInterval = 30 * 60

    /// A timeline asked for within this long of a tap is the reload the tap
    /// asked for: it draws from saved readings, without the network, so the
    /// page changes at once.
    static let tapReloadWindow: TimeInterval = 15

    /// The order the index label steps through, as the edit sheet lists them.
    static let indexCycle: [AirIndexTypes] = [.aqi, .pm25, .pm10, .o3, .co, .so2, .no2]

    /// One widget's state in the app group. The configuration is part of the
    /// key, so changing it in the edit sheet starts afresh. Two widgets of the
    /// same size and settings share their state: WidgetKit doesn't tell them
    /// apart.
    static func key(family: String, station: String, index: String) -> String {
        "\(family)|\(station)|\(index)"
    }

    /// The stations to page through: the widget's own station first, then the
    /// favourites in the reader's order, each once. `favouriteIds` should hold
    /// only favourites with a saved reading, since a tap never fetches.
    static func pageIds(defaultId: Int?, favouriteIds: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return ([defaultId].compactMap { $0 } + favouriteIds).filter { seen.insert($0).inserted }
    }

    /// The ‹ › buttons need at least two saved favourites and two stations to
    /// show.
    static func showsPager(favouriteCount: Int, pageCount: Int) -> Bool {
        favouriteCount >= 2 && pageCount >= 2
    }

    /// The page shown: the stored station's place in `pageIds`, or 0 (the
    /// default page) when nothing is stored, the last tap is
    /// `resetInterval` old, or the station is no longer there.
    static func currentPage(_ state: WidgetPageState, pageIds: [Int], now: Date) -> Int {
        guard let stationId = state.stationId,
              let tappedAt = state.tappedAt,
              now.timeIntervalSince(tappedAt) < resetInterval,
              let page = pageIds.firstIndex(of: stationId)
        else { return 0 }
        return page
    }

    /// The page `step` away from `page`, wrapping at both ends.
    static func page(from page: Int, step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((page + step) % count + count) % count
    }

    /// What a button stores to show `page`: nil for the default page.
    static func target(ofPage page: Int, in pageIds: [Int]) -> Int? {
        guard page > 0, pageIds.indices.contains(page) else { return nil }
        return pageIds[page]
    }

    /// When a paged widget goes back to its default page, or nil when it is
    /// on the default page.
    static func resetDate(_ state: WidgetPageState, pageIds: [Int], now: Date) -> Date? {
        guard currentPage(state, pageIds: pageIds, now: now) > 0, let tappedAt = state.tappedAt else { return nil }
        return tappedAt.addingTimeInterval(resetInterval)
    }

    /// The index after `index` in `indexCycle`, wrapping.
    static func nextIndex(after index: AirIndexTypes) -> AirIndexTypes {
        guard let position = indexCycle.firstIndex(of: index) else { return indexCycle[0] }
        return indexCycle[(position + 1) % indexCycle.count]
    }

    /// The index to draw: the cycled one, or `configured` from the edit sheet.
    static func index(_ state: WidgetPageState, configured: AirIndexTypes) -> AirIndexTypes {
        state.index.flatMap(AirIndexTypes.init(rawValue:)) ?? configured
    }

    /// True when this timeline is the reload a tap asked for, so it draws
    /// from saved readings instead of fetching.
    static func isTapReload(_ state: WidgetPageState, now: Date) -> Bool {
        guard let tappedAt = state.tappedAt else { return false }
        let since = now.timeIntervalSince(tappedAt)
        return since >= 0 && since < tapReloadWindow
    }

    /// After a ‹ › tap: show `stationId` (nil for the default page).
    static func paged(_ state: WidgetPageState, to stationId: Int?, now: Date) -> WidgetPageState {
        var state = state
        state.stationId = stationId
        state.tappedAt = now
        return state
    }

    /// True when the page stored in `state` is `resetInterval` past its last
    /// tap, so the widget is back on its own station whatever is stored.
    static func isExpired(_ state: WidgetPageState, now: Date) -> Bool {
        guard let tappedAt = state.tappedAt else { return true }
        return now.timeIntervalSince(tappedAt) >= resetInterval
    }

    /// After a tap on the index label: show `index`. A page that already
    /// went back to the default stays there: the tap doesn't revive it.
    static func cycled(_ state: WidgetPageState, to index: AirIndexTypes, now: Date) -> WidgetPageState {
        var state = state
        if isExpired(state, now: now) {
            state.stationId = nil
        }
        state.index = index.rawValue
        state.tappedAt = now
        return state
    }

    /// After a scheduled timeline: with new readings (`hasNewData`), back to
    /// the default page. Offline, or when the request failed, the page stays
    /// and only the 30-minute rule sends it back; an expired page is cleared.
    /// The cycled index stays.
    static func refreshed(_ state: WidgetPageState, hasNewData: Bool, now: Date) -> WidgetPageState {
        var state = state
        if hasNewData || isExpired(state, now: now) {
            state.stationId = nil
        }
        state.refreshedAt = now
        return state
    }

    /// What a scheduled timeline saves after its fetch. `current` is the
    /// state read again after the fetch, `readBefore` the one read before
    /// it. A tap in between (a different `tappedAt`) is newer than the
    /// readings, so its page and index stay; otherwise `refreshed`.
    static func afterFetch(
        _ current: WidgetPageState, readBefore: WidgetPageState, hasNewData: Bool, now: Date
    ) -> WidgetPageState {
        guard current.tappedAt == readBefore.tappedAt else {
            var state = current
            state.refreshedAt = now
            return state
        }
        return refreshed(current, hasNewData: hasNewData, now: now)
    }
}

/// `WidgetPageState` per widget, in the app group's defaults. One key per
/// widget: a tap's intent and another widget's timeline run in separate
/// processes, and a shared blob rewritten by both would lose one's write.
enum WidgetPageStore {
    private static let prefix = "widgetPageState."

    static func defaultsKey(for widgetKey: String) -> String {
        prefix + widgetKey
    }

    static func state(for widgetKey: String, in defaults: UserDefaults) -> WidgetPageState {
        defaults.data(forKey: defaultsKey(for: widgetKey))
            .flatMap { try? JSONDecoder().decode(WidgetPageState.self, from: $0) } ?? WidgetPageState()
    }

    static func save(_ state: WidgetPageState, for widgetKey: String, in defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(state), forKey: defaultsKey(for: widgetKey))
    }
}
