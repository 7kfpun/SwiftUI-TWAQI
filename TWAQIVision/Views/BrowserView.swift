//
//  BrowserView.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// The iOS app's other tabs — favourites, the station search and help — in a
/// window beside the map, which takes the place of the map tab.
struct BrowserView: View {
    static let id = "browser"

    #if DEBUG
    @State private var tab = ScreenshotLaunch.browserTab ?? "favourites"
    #else
    @State private var tab = "favourites"
    #endif

    var body: some View {
        TabView(selection: $tab) {
            FavouritesTab()
                .tabItem { Label("Tabbar.favourites", systemImage: "heart") }
                .tag("favourites")

            StationSearchTab()
                .tabItem { Label("Tabbar.details_list", systemImage: "list.bullet") }
                .tag("search")

            HelpTab()
                .tabItem { Label("Tabbar.help", systemImage: "questionmark.circle") }
                .tag("help")
        }
    }
}

// MARK: - Rows

/// The iOS list row, plus what a list row can do here: drag it out to pin
/// the station, or open it in its own window.
private struct StationLink: View {
    let station: Pollutant
    var showsReading = true

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationLink(value: station.stationId) {
            StationRow(
                title: station.displayName,
                subtitle: station.displayLocality,
                reading: showsReading ? .init(aqi: station.aqi, publishTime: station.publishTime) : nil
            )
        }
        .onDrag {
            StationActivity.itemProvider(stationId: station.stationId, title: station.displayName)
        }
        .contextMenu {
            Button {
                openWindow(id: StationWindow.id, value: station.stationId)
            } label: {
                Label("Vision.open_in_new_window", systemImage: "macwindow.badge.plus")
            }
        }
    }
}

private extension View {
    func stationDestinations() -> some View {
        navigationDestination(for: Int.self) { StationDetailView(stationId: $0) }
    }
}

// MARK: - Favourites

private struct FavouritesTab: View {
    @Environment(StationStore.self) private var store
    @Environment(Favourites.self) private var favourites

    var body: some View {
        NavigationStack {
            Group {
                if favourites.stationIds.isEmpty {
                    EmptyStateView(icon: "heart", message: "Favourites.add_your_first_favourite_station")
                } else {
                    List {
                        ForEach(favourites.stationIds, id: \.self) { id in
                            if let station = store.station(id) {
                                StationLink(station: station)
                            } else {
                                // Saved, but not in the latest readings (yet).
                                NavigationLink(value: id) {
                                    StationRow(title: "#\(id)", subtitle: nil, reading: nil)
                                }
                            }
                        }
                        .onDelete { favourites.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("FavouriteList.favourites")
            .toolbar {
                if !favourites.stationIds.isEmpty {
                    Button("Favourites.remove_all_your_saved_stations", role: .destructive) {
                        favourites.removeAll()
                    }
                }
            }
            .stationDestinations()
        }
    }
}

// MARK: - Search

private struct StationSearchTab: View {
    @Environment(StationStore.self) private var store
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.stations.isEmpty {
                    EmptyStateView(icon: "list.bullet", message: "Details.no_data")
                } else {
                    List {
                        if searchText.isEmpty, let nearest = store.nearestStation {
                            Section("Vision.nearest_station") {
                                StationLink(station: nearest)
                            }
                        }
                        ForEach(groupedStations, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.stations, id: \.stationId) { StationLink(station: $0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("DetailsList.details")
            .searchable(text: $searchText, prompt: Text("DetailsList.search"))
            .toolbar {
                Button {
                    Task { await store.selectNearest() }
                } label: {
                    Label("Vision.find_nearest", systemImage: "location")
                }
                .disabled(store.isLocating)
            }
            .stationDestinations()
        }
    }

    /// Matches bucketed by air-quality region in first-seen (roughly north to
    /// south) order, as on iOS.
    private var groupedStations: [(title: String, stations: Pollutants)] {
        let matches = searchText.isEmpty
            ? store.stations
            : store.stations.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.nameLocal.localizedCaseInsensitiveContains(searchText)
                    || ($0.displayLocality?.localizedCaseInsensitiveContains(searchText) ?? false)
            }

        var order: [String] = []
        var buckets: [String: Pollutants] = [:]
        for station in matches {
            let key = station.displayArea ?? ""
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(station)
        }
        return order.map { (title: $0, stations: buckets[$0] ?? []) }
    }
}

// MARK: - Help

/// The iOS Help tab without its push-notification and in-app-purchase
/// sections: there's no OneSignal on visionOS, and Pro removes ads this app
/// doesn't show.
private struct HelpTab: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LinkPages.allCases) { page in
                        Link(destination: page.url) {
                            HStack {
                                Text(page.title)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("Help.contact_us", systemImage: "envelope")
                }

                Section {
                    ForEach(DefinitionPages.allCases) { page in
                        NavigationLink(page.title) { IndexGuideView(page: page) }
                    }
                } header: {
                    Label("Help.definition", systemImage: "book")
                }

                Section {
                    LabeledContent("Vision.version", value: appVersion)
                } header: {
                    Label("Vision.about", systemImage: "info.circle")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Help.data_provided_by_government")
                        Text("Vision.map_data")
                    }
                }
            }
            .navigationTitle("Help.help")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
