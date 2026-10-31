//
//  DetailsListView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsListView: View {
    @EnvironmentObject var settings: SettingsStore
    // Owns its view model — see the note in DetailsView.
    @StateObject private var viewModel: DetailsListViewModel

    @State private var searchText = ""

    var body: some View {
        AdaptiveNavigation {
            Group {
                if viewModel.stations.isEmpty, viewModel.loadFailed {
                    OfflineEmptyStateView(retry: getData)
                } else if viewModel.stations.isEmpty {
                    EmptyStateView(icon: "list.bullet", message: "Details.no_data")
                } else {
                    list
                }
            }
            .navigationBarTitle("DetailsList.details")
            // Native search field: replaces the hand-rolled TextField and gives
            // scroll-to-reveal, a cancel button, and keyboard dismissal for free.
            // On the list itself so it stays in the list column when the
            // window is wide enough for two.
            .searchable(text: $searchText, prompt: Text("DetailsList.search"))
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdDetailsListFooter")!)
            }
        }
        .onAppear(perform: getData)
    }

    private var list: some View {
        List {
            ForEach(groupedStations, id: \.title) { group in
                Section(header: Text(group.title)) {
                    ForEach(group.stations, id: \.self) { station in
                        NavigationLink(
                            destination: DetailsView(stationId: station.id)
                                .environmentObject(settings)
                        ) {
                            StationRow(
                                title: station.displayName,
                                subtitle: station.displayLocality,
                                reading: nil
                            )
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    /// Matched stations bucketed by air-quality region, regions in first-seen
    /// (roughly north-to-south) order rather than alphabetically.
    private var groupedStations: [(title: String, stations: Stations)] {
        let matches = searchText.isEmpty
            ? viewModel.stations
            : viewModel.stations.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.nameLocal.localizedCaseInsensitiveContains(searchText)
                    || ($0.displayLocality?.localizedCaseInsensitiveContains(searchText) ?? false)
            }

        var order: [String] = []
        var buckets: [String: Stations] = [:]
        for station in matches {
            let key = station.displayArea ?? ""
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(station)
        }

        return order.map { (title: $0, stations: buckets[$0] ?? []) }
    }

    init() {
        _viewModel = StateObject(wrappedValue: DetailsListViewModel())
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct DetailsListView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsListView().environmentObject(SettingsStore())
    }
}
