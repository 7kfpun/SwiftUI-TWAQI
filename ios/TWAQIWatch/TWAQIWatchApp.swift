//
//  TWAQIWatchApp.swift
//  TWAQIWatch
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import StoreKit
import SwiftUI
import WidgetKit

@main
struct TWAQIWatchApp: App {
    init() {
        // Readings cached more than a week ago are never shown; drop them.
        WatchStore.purgeExpiredReadings()
        // Locked-style hits the complications queued go to the phone's Firebase.
        PhoneRelay.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

@MainActor
final class WatchModel: ObservableObject {
    /// How the station on screen was chosen.
    enum Source {
        /// Picked by hand in the station list.
        case pinned
        /// Home, from the reader's location.
        case closest
        /// Home without a location: the station nearest 中正.
        case fallback
    }

    @Published private(set) var reading: WatchReading? = WatchStore.latestReading
    @Published private(set) var home: WatchReading? = WatchStore.homeReading
    @Published private(set) var history: HistoricalPollutants = []
    @Published private(set) var source: Source = WatchStore.pinnedStationId == nil ? .fallback : .pinned
    @Published private(set) var stations: Pollutants = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var failed = false
    @Published private(set) var isPro = WatchPro.isUnlocked
    /// The phone's favourites, in its order (FOX-174).
    @Published private(set) var favouriteIds: [Int] = WatchStore.favouriteStationIds

    private let locator = Locator()

    /// Half the phone's 24: a day of bars is too thin to read on a watch, and
    /// the recent hours are what matter at a glance.
    static let historyHours = 12

    var isHome: Bool { source != .pinned }

    /// Re-asks StoreKit; a purchase or refund on any device lands here.
    /// The app and the face complication are free; only the complication's
    /// number and other styles depend on the answer.
    func checkPro() async {
        let unlocked = await WatchPro.refresh()
        guard unlocked != isPro else { return }
        isPro = unlocked
        WidgetCenter.shared.reloadAllTimelines()
        await SmartStackHints.update(isPro: unlocked)
    }

    /// Purchases completed outside the paywall: Ask to Buy approvals, or a
    /// buy on the phone syncing over.
    func observeTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
            }
            await checkPro()
        }
    }

    /// Set when a refresh is asked for while one is in flight (a swipe moved
    /// the pin): the running refresh goes round again for the new pin.
    private var rerunRequested = false

    func refresh() async {
        if isLoading {
            rerunRequested = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        repeat {
            rerunRequested = false
            await refreshOnce()
        } while rerunRequested
    }

    private func refreshOnce() async {
        do {
            let pollutant: Pollutant?
            if let stationId = WatchStore.pinnedStationId {
                source = .pinned
                pollutant = try await WatchAPI.currentPollutant(stationId: stationId)
            } else {
                // Home needs the whole list to find the nearest station, which
                // also fills the picker for free.
                stations = try await WatchAPI.currentPollutants()
                let location = await locator.current()
                source = location == nil ? .fallback : .closest
                pollutant = WatchAPI.closest(to: location ?? WatchAPI.defaultLocation, in: stations)
                if let pollutant {
                    home = WatchReading(pollutant)
                    WatchStore.homeReading = home
                    WatchStore.homeIsLocated = location != nil
                }
            }

            guard let pollutant else { throw WatchAPI.Failure.badResponse }
            // The pin moved while this fetched: the rerun loads the new one.
            guard WatchFavourites.mayStore(fetched: pollutant.stationId, pinned: WatchStore.pinnedStationId) else { return }
            if pollutant.stationId != reading?.stationId {
                history = []
            }
            store(WatchReading(pollutant))
            failed = false

            // The reading is already on screen; a missing chart shouldn't fail it.
            isLoadingHistory = true
            defer { isLoadingHistory = false }
            let fetchedHistory = (try? await WatchAPI.history(stationId: pollutant.stationId, limit: Self.historyHours)) ?? []
            guard WatchFavourites.mayStore(fetched: pollutant.stationId, pinned: WatchStore.pinnedStationId) else { return }
            history = fetchedHistory
        } catch {
            failed = true
        }
    }

    func loadStations() async {
        do {
            stations = try await WatchAPI.currentPollutants()
            failed = false
        } catch {
            failed = true
        }
    }

    /// Pins a station, or returns to home with `nil`.
    func pin(_ pollutant: Pollutant?) {
        WatchStore.pinnedStationId = pollutant?.stationId
        if let pollutant {
            source = .pinned
            history = []
            store(WatchReading(pollutant))
        }
        Task { await refresh() }
    }

    func reloadFavourites() {
        favouriteIds = WatchStore.favouriteStationIds
    }

    /// Pins a station by id when the reader swipes to it. The complications
    /// follow, as they do for a pick in the list; the reading shows at once
    /// from the cached favourite and refreshes behind it.
    func pin(stationId: Int) {
        guard stationId != reading?.stationId || source != .pinned else { return }
        WatchStore.pinnedStationId = stationId
        source = .pinned
        if let cached = WatchStore.favouriteReadings.first(where: { $0.stationId == stationId }) {
            store(cached)
        }
        Task { await refresh() }
    }

    private func store(_ reading: WatchReading) {
        self.reading = reading
        WatchStore.latestReading = reading
        WidgetCenter.shared.reloadAllTimelines()
        // The Smart Stack's windows follow the station and its reading.
        let isPro = isPro
        Task { await SmartStackHints.update(isPro: isPro) }
    }
}

struct RootView: View {
    @StateObject private var model = WatchModel()
    /// The page under the finger. It follows a swipe at once; the model's
    /// reading catches up behind it.
    @State private var selection: Int?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            pager
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchFavouritesChanged)) { _ in
            model.reloadFavourites()
        }
        .task { await model.observeTransactions() }
        .task {
            await model.checkPro()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reloadFavourites()
                PhoneRelay.shared.flush()
                Task {
                    await model.checkPro()
                    await model.refresh()
                }
            }
        }
    }

    /// Swipe between the favourites; with none, or only the one on screen,
    /// it is the plain reading with the station list behind the toolbar button.
    @ViewBuilder
    private var pager: some View {
        let pages = WatchFavourites.pages(favourites: model.favouriteIds, current: model.reading?.stationId)

        if pages.count < 2 {
            ReadingView(model: model)
        } else {
            TabView(selection: Binding(
                get: { selection ?? model.reading?.stationId ?? pages[0] },
                set: {
                    selection = $0
                    model.pin(stationId: $0)
                }
            )) {
                ForEach(pages, id: \.self) { id in
                    // Only the page on screen is built: the model holds one station.
                    Group {
                        if model.reading?.stationId == id {
                            ReadingView(model: model)
                        } else if model.failed && !model.isLoading {
                            Image(systemName: "exclamationmark.triangle")
                                .onTapGesture { Task { await model.refresh() } }
                        } else {
                            ProgressView()
                        }
                    }
                    .tag(id)
                }
            }
            .tabViewStyle(.page)
        }
    }
}
