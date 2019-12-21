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

                AdBannerView(adUnitID: getEnv("AdUnitIdFavouritesFooter")!)
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
