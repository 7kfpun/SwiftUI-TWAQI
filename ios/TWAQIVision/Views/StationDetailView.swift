//
//  StationDetailView.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The iOS station page, built from the same section views in the same order:
/// what it is, where that sits on the scale, what's in the air and how it has
/// moved over the day, the wind, what to do about it, where the station is.
///
/// Leaves out the iOS page's notification thresholds: push alerts are only
/// wired up for the iPhone app.
struct StationDetailView: View {
    let stationId: Int

    @Environment(StationStore.self) private var store
    @Environment(Favourites.self) private var favourites
    @Environment(\.openWindow) private var openWindow

    /// Fetched when the station isn't among the store's readings yet.
    @State private var fetched: Pollutant?
    @State private var history: HistoricalPollutants = []
    /// Local to this page, as on iOS: it picks what the chart shows and
    /// must not re-score the map.
    @State private var selectedPollutant = AirIndexTypes.aqi

    private var pollutant: Pollutant? { store.station(stationId) ?? fetched }
    private var currentAqi: Double { pollutant?.aqi ?? history.last?.aqi ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StationHeaderView(
                    title: pollutant?.displayName ?? "",
                    locality: pollutant?.displayLocality,
                    area: pollutant?.displayArea,
                    stationType: pollutant?.stationType ?? .unknown,
                    aqi: currentAqi,
                    publishTime: pollutant?.publishTime ?? history.last?.publishTime
                )

                AqiScaleView(aqi: currentAqi)
                    .padding(.top, 4)
                    .padding(.bottom, 16)

                Divider()

                if let pollutant {
                    PollutantGridView(pollutant: pollutant, selected: $selectedPollutant)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                }

                DetailsHistoryView(historicalPollutants: history, airIndexType: selectedPollutant)

                Divider()

                if let pollutant {
                    WindView(wind: pollutant.wind, tint: tint(for: pollutant))
                        .padding(.vertical, 16)
                    Divider()
                }

                if currentAqi > 0 {
                    HealthGuidanceView(aqi: currentAqi)
                        .padding(.vertical, 16)
                    Divider()
                }

                if let pollutant {
                    let location = StationLocationView(pollutant: pollutant)
                    if location.hasContent {
                        location.padding(.vertical, 16)
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        // The shared iOS sections colour their text by air status, chosen to
        // read on white. Over visionOS's light glass in a bright room the
        // greens and yellows washed out; a darker glass gives them the
        // contrast they have in dark mode.
        .background(.black.opacity(0.35))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.selectedStationId = stationId
                    if !store.isMapOpen {
                        openWindow(id: TWAQIVisionApp.mapId)
                    }
                } label: {
                    Label("Vision.show_on_map", systemImage: "map")
                }

                Button {
                    favourites.toggle(stationId)
                } label: {
                    Label(
                        "Tabbar.favourites",
                        systemImage: favourites.contains(stationId) ? "heart.fill" : "heart"
                    )
                }
            }
        }
        .task(id: stationId) {
            await load()
        }
    }

    /// Band colour of the pollutant the page is showing, so the wind arrow
    /// matches the highlighted reading and the chart, as on iOS.
    private func tint(for pollutant: Pollutant) -> Color {
        let status = AirStatuses.checkAirStatus(
            airIndexType: selectedPollutant,
            value: pollutant.getValue(airIndexType: selectedPollutant)
        )
        return Color(status.getColor())
    }

    private func load() async {
        async let history = try? WatchAPI.history(stationId: stationId)
        if store.station(stationId) == nil {
            fetched = try? await WatchAPI.currentPollutant(stationId: stationId)
        }
        self.history = await history ?? []
    }
}
