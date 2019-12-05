//
//  FavouriteListView.swift
//  TWAQI
//
//  Created by kf on 4/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct FavouriteListView: View {
    @ObservedObject var viewModel: FavouriteListViewModel

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    ForEach(self.viewModel.favouritePollutants, id: \.self) {pollutant in
                        FavouriteRow(pollutant: pollutant)
                    }

                    if !self.viewModel.favouritePollutants.isEmpty {
                        HStack {
                            Spacer()
                            Button(action: self.removeAll) {
                                Text("Favourites.cancel_all_notification")
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

                AdBannerView(adUnitID: getEnv("AdUnitIdDetailsListFooter")!)
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
        print("removeAll", self.viewModel.stationSettings)
        for (_, stationSetting) in self.viewModel.stationSettings {
            OneSignalManager.sendTags(
                tags: stationSetting.getDisabledTags()
            ) { result in
                switch result {
                case .success(let result):
                    print(result)
                    self.viewModel.getData()
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
    }
}

struct FavouritesListView_Previews: PreviewProvider {
    static var previews: some View {
        FavouriteListView()
    }
}
