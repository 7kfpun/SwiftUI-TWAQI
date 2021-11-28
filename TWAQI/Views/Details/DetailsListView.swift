//
//  DetailsListView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsListView: View {
    @ObservedObject var viewModel: DetailsListViewModel

    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    TextField(LocalizedStringKey("DetailsList.search"), text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()

                    if self.viewModel.stations.count > 0 {
                        if searchText.isEmpty {
                            ForEach(self.viewModel.stations, id: \.self) {station in
                                DetailsRow(station: station)
                            }
                        } else {
                            ForEach(
                                self.viewModel.stations.filter {
                                    $0.name.localizedCaseInsensitiveContains(self.searchText)
                                    || $0.nameLocal.localizedCaseInsensitiveContains(self.searchText)
                                    || self.searchText.isEmpty
                                }, id: \.self
                            ) {station in
                                DetailsRow(station: station)
                            }
                        }
                    }

                    Spacer().frame(height: 50)
                }

                AdBannerView(adUnitID: getEnv("AdUnitIdDetailsListFooter")!)
            }
            .navigationBarTitle("DetailsList.details")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: getData)
    }

    init() {
        self.viewModel = DetailsListViewModel()
    }

    private func getData() {
        self.viewModel.getData()
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
}

struct DetailsListView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsListView()
    }
}
