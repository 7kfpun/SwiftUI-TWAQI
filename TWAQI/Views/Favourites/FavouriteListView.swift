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
    @ObservedObject var viewModel: FavouriteListViewModel

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    if !settings.savedFavouriteStations.isEmpty {
                        ForEach(self.viewModel.favouritePollutants, id: \.self) {pollutant in
                            FavouriteRow(pollutant: pollutant)
                        }

                        HStack {
                            Spacer()
                            Button(action: self.removeAll) {
                                Text("Favourites.remove_all_your_saved_stations")
                            }
                            Spacer()
                        }
                        .padding(.top, 10)
                    } else {
                        HStack {
                            Spacer()
                            Text("Favourites.add_your_first_favourite_station")
                            Spacer()
                        }
                        .padding(.top, 50)
                    }

                    Spacer().frame(height: 80)
                }

                if !viewModel.isCustomAdLoading {
                    if viewModel.isShowCustomAd {
                        CustomAdView(customAd: viewModel.customAd)
                            .onAppear(perform: submitImpressionEvent)
                    } else {
                        AdBannerView(adUnitID: getEnv("AdUnitIdFavouritesFooter")!)
                    }
                }
            }
            .navigationBarTitle("FavouriteList.favourites")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            self.getData()
        }
    }

    init() {
        self.viewModel = FavouriteListViewModel()
    }

    private func getData() {
        self.viewModel.getData()
        self.viewModel.getCustomAd()
        Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { (_) in
            // Schedule in seconds
            self.viewModel.getCustomAd()
        }
    }

    private func submitImpressionEvent() {
        if viewModel.isShowCustomAd {
            if let customAd = viewModel.customAd {
                var components = URLComponents(string: customAd.imageUrl)!
                components.query = nil

                TrackingManager.logEvent(eventName: "ad_custom_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])

                TrackingManager.logEvent(eventName: "ad_custom_\(customAd.name)_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])
            }
        }
    }

    private func removeAll() {
        settings.savedFavouriteStations = []
    }
}

struct FavouritesListView_Previews: PreviewProvider {
    static var previews: some View {
        FavouriteListView()
    }
}
