//
//  AppRouter.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Combine
import Foundation

/// Screens the app was asked to open by URL. One per window scene;
/// `ContentView` presents from it so a link works whichever tab is showing.
final class AppRouter: ObservableObject {
    /// A station page opened by link: the Control Center control, or the
    /// "Open station" shortcut (FOX-74).
    struct OpenedStation: Identifiable, Equatable {
        let id: Int
    }

    @Published var showingPro = false

    @Published var openedStation: OpenedStation?

    /// Where the link that opened the Pro screen came from, handed to
    /// `ProView`, which logs it with each funnel step.
    private(set) var proSource: ProScreenSource = .deepLink

    /// Opens what `url` asks for. Returns false when it is ignored: not one
    /// of our URLs, the Pro screen for someone who already has Pro, or a
    /// station not in `isKnownStation`. Only an accepted link is logged.
    @discardableResult
    func open(_ url: URL, isPro: Bool, isKnownStation: (Int) -> Bool = KnownStations.contains) -> Bool {
        guard let link = DeepLink.route(url, isPro: isPro, isKnownStation: isKnownStation) else { return false }
        switch link {
        case .pro(let source):
            proSource = source
            showingPro = true
        case .station(let id, let source):
            TrackingManager.logEvent(.stationLinkOpened, parameters: [
                "source": source.rawValue,
                "stationId": id,
            ])
            openedStation = OpenedStation(id: id)
        }
        return true
    }
}

/// Stations the app has seen, for checking a `twaqi://station` link
/// (FOX-74). The control and the "Open station" shortcut only ever link to a
/// favourite or the station home resolved to, so those always pass; the
/// station list and the readings cached for the map cover the rest. An id in
/// none of them is dropped rather than opening a page for nothing.
enum KnownStations {
    static func contains(_ id: Int) -> Bool {
        if SettingsStore().savedFavouriteStations.contains(id) { return true }
        let shared = WatchStore.favouriteStationIds
            + [WatchStore.pinnedStationId].compactMap { $0 }
            + (WatchStore.favouriteReadings + [WatchStore.latestReading, WatchStore.homeReading].compactMap { $0 })
                .map(\.stationId)
        if shared.contains(id) { return true }
        if PollutantCache.shared.pollutant(stationId: id) != nil { return true }
        return DetailsListViewModel.cachedStationIds().contains(id)
    }
}
