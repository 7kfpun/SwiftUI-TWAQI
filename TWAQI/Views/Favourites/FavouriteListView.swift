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

    /// Stations waiting on the reader before they leave Favourites, because
    /// at least one has an alert that would be turned off with it.
    @State private var pendingRemoval: PendingRemoval?

    private struct PendingRemoval {
        var stationIds: [Int]
        var isAll: Bool

        static let oneTitle: LocalizedStringKey = "Favourites.remove_station_with_alerts_title"
        static let oneMessage: LocalizedStringKey = "Favourites.remove_station_with_alerts_message"
        static let allTitle: LocalizedStringKey = "Favourites.remove_all_with_alerts_title"
        static let allMessage: LocalizedStringKey = "Favourites.remove_all_with_alerts_message"
    }

    var body: some View {
        AdaptiveNavigation {
            Group {
                if settings.savedFavouriteStations.isEmpty {
                    EmptyStateView(
                        icon: "heart",
                        message: "Favourites.add_your_first_favourite_station"
                    )
                } else if viewModel.favouritePollutants.isEmpty {
                    // Favourites are saved but none can be shown yet: say
                    // why, rather than look like there are none.
                    if viewModel.loadFailed {
                        OfflineEmptyStateView(retry: getData)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 64)
                    }
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
        .alert(
            Text(pendingRemoval?.isAll == true ? PendingRemoval.allTitle : PendingRemoval.oneTitle),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { pending in
            Button(role: .destructive) {
                commitRemoval(pending)
            } label: {
                Text("Favourites.remove_and_turn_off_alerts")
            }
            Button(role: .cancel, action: {}) {
                Text("Favourites.cancel")
            }
        } message: { pending in
            Text(pending.isAll ? PendingRemoval.allMessage : PendingRemoval.oneMessage)
        }
    }

    private var list: some View {
        List {
            if viewModel.isShowingLastGood {
                Section {
                    OfflineNotice()
                }
            }

            Section {
                ForEach(viewModel.favouritePollutants, id: \.self) { pollutant in
                    NavigationLink(
                        destination: DetailsView(stationId: pollutant.stationId)
                            .environmentObject(settings)
                    ) {
                        StationRow(
                            title: pollutant.displayName,
                            subtitle: pollutant.displayLocality,
                            reading: .init(
                                aqi: pollutant.aqi,
                                publishTime: pollutant.publishTime,
                                pollutants: Self.keyPollutants.map {
                                    .init(type: $0, value: pollutant.getValue(airIndexType: $0))
                                }
                            ),
                            alertsOn: viewModel.alertedStationIds.contains(pollutant.stationId)
                        )
                    }
                }
                .onDelete(perform: remove)
                .onMove(perform: move)
            }
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

    /// The pollutants that most often set Taiwan's AQI, shown on each row.
    /// The station screen has all six.
    private static let keyPollutants: [AirIndexTypes] = [.pm25, .pm10, .o3]

    init() {
        _viewModel = StateObject(wrappedValue: FavouriteListViewModel())
    }

    private func getData() {
        self.viewModel.getData()
    }

    private func remove(at offsets: IndexSet) {
        let ids = offsets.map { viewModel.favouritePollutants[$0].stationId }
        request(PendingRemoval(stationIds: ids, isAll: false))
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
        request(PendingRemoval(stationIds: settings.savedFavouriteStations, isAll: true))
    }

    /// Removes at once, unless an alert would go with it: then asks first.
    private func request(_ removal: PendingRemoval) {
        if viewModel.needsConfirmation(toRemove: removal.stationIds) {
            pendingRemoval = removal
        } else {
            commitRemoval(removal)
        }
    }

    private func commitRemoval(_ removal: PendingRemoval) {
        viewModel.remove(stationIds: removal.stationIds)
        pendingRemoval = nil

        if removal.isAll {
            TrackingManager.logEvent(eventName: "favourite_station_all_removed")
        } else {
            TrackingManager.logEvent(eventName: "favourite_station_saved", parameters: [
                "label": "off",
                "stationId": removal.stationIds.first ?? 0,
            ])
        }
    }
}

struct FavouritesListView_Previews: PreviewProvider {
    static var previews: some View {
        FavouriteListView().environmentObject(SettingsStore())
    }
}
