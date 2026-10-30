//
//  FavouriteListView.swift
//  TWAQI
//
//  Created by kf on 4/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct FavouriteListView: View {
    @EnvironmentObject var settings: SettingsStore
    // Owns its view model — see the note in DetailsView.
    @StateObject private var viewModel: FavouriteListViewModel

    var body: some View {
        AdaptiveNavigation {
            Group {
                if settings.savedFavouriteStations.isEmpty {
                    EmptyStateView(
                        icon: "heart",
                        message: "Favourites.add_your_first_favourite_station"
                    )
                } else {
                    list
                }
            }
            .navigationBarTitle("FavouriteList.favourites")
            .navigationBarItems(leading: editButton, trailing: removeAllButton)
            // Insets the scroll content so the last row clears the banner,
            // instead of padding the content by a guessed height.
            .safeAreaInset(edge: .bottom) {
                AdBannerView(adUnitID: getEnv("AdUnitIdFavouritesFooter")!)
            }
        }
        .onAppear(perform: getData)
    }

    private var list: some View {
        List {
            ForEach(viewModel.favouritePollutants, id: \.self) { pollutant in
                NavigationLink(
                    destination: DetailsView(stationId: pollutant.stationId)
                        .environmentObject(settings)
                ) {
                    StationRow(
                        title: pollutant.displayName,
                        subtitle: pollutant.displayLocality,
                        reading: .init(aqi: pollutant.aqi, publishTime: pollutant.publishTime)
                    )
                }
            }
            .onDelete(perform: remove)
            .onMove(perform: move)
        }
        .listStyle(InsetGroupedListStyle())
    }

    @ViewBuilder
    private var editButton: some View {
        if !settings.savedFavouriteStations.isEmpty {
            EditButton()
        }
    }

    @ViewBuilder
    private var removeAllButton: some View {
        if !settings.savedFavouriteStations.isEmpty {
            Button(action: removeAll) {
                Text("Favourites.remove_all_your_saved_stations")
                    .font(.footnote)
            }
        }
    }

    init() {
        _viewModel = StateObject(wrappedValue: FavouriteListViewModel())
    }

    private func getData() {
        self.viewModel.getData()
    }

    private func remove(at offsets: IndexSet) {
        let removedIds = offsets.map { viewModel.favouritePollutants[$0].stationId }
        settings.savedFavouriteStations.removeAll { removedIds.contains($0) }
        viewModel.favouritePollutants.remove(atOffsets: offsets)

        TrackingManager.logEvent(eventName: "favourite_station_saved", parameters: [
            "label": "off",
            "stationId": removedIds.first ?? 0,
        ])
    }

    /// Saves the new order, which the widget's first favourite follows.
    private func move(from source: IndexSet, to destination: Int) {
        viewModel.favouritePollutants.move(fromOffsets: source, toOffset: destination)
        let listed = viewModel.favouritePollutants.map(\.stationId)
        // Saved stations the API didn't return keep their place after the rest.
        settings.savedFavouriteStations = listed + settings.savedFavouriteStations.filter { !listed.contains($0) }
        TrackingManager.logEvent(eventName: "favourite_station_reordered")
    }

    private func removeAll() {
        settings.savedFavouriteStations = []
        viewModel.favouritePollutants = []
        TrackingManager.logEvent(eventName: "favourite_station_all_removed")
    }
}

struct FavouritesListView_Previews: PreviewProvider {
    static var previews: some View {
        FavouriteListView().environmentObject(SettingsStore())
    }
}
