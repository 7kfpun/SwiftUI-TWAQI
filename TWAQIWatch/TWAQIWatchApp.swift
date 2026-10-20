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

    private let locator = Locator()

    /// Half the phone's 24: a day of bars is too thin to read on a watch, and
    /// the recent hours are what matter at a glance.
    static let historyHours = 12

    var isHome: Bool { source != .pinned }

    /// Re-asks StoreKit; a purchase or refund on any device lands here.
    func checkPro() async {
        let unlocked = await WatchPro.refresh()
        guard unlocked != isPro else { return }
        isPro = unlocked
        WidgetCenter.shared.reloadAllTimelines()
        if unlocked {
            await refresh()
        }
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

    func refresh() async {
        // Locked: nothing is shown, so nothing is fetched.
        guard isPro, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

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
                }
            }

            guard let pollutant else { throw WatchAPI.Failure.badResponse }
            if pollutant.stationId != reading?.stationId {
                history = []
            }
            store(WatchReading(pollutant))
            failed = false

            // The reading is already on screen; a missing chart shouldn't fail it.
            isLoadingHistory = true
            defer { isLoadingHistory = false }
            history = (try? await WatchAPI.history(stationId: pollutant.stationId, limit: Self.historyHours)) ?? []
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

    private func store(_ reading: WatchReading) {
        self.reading = reading
        WatchStore.latestReading = reading
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct RootView: View {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            if model.isPro {
                ReadingView(model: model)
            } else {
                PaywallView(model: model)
            }
        }
        .task { await model.observeTransactions() }
        .task {
            await model.checkPro()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.checkPro()
                    await model.refresh()
                }
            }
        }
    }
}
