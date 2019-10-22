//
//  DetailsListView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMobileAds
import SwiftUI

struct DetailsListView: View {

    @State private var searchText = ""

    var stationGroups: StationGroups

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    TextField("Search", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()

                    if searchText.isEmpty {
                        ForEach(stationGroups, id: \.self) {stationGroup in
                            DetailsGroup(stationGroup: stationGroup)
                        }
                    } else {
                        ForEach(stationGroups, id: \.self) {stationGroup in
                            ForEach(stationGroup.stations.filter {$0.name.hasPrefix(self.searchText) || self.searchText.isEmpty}, id: \.self) {station in
                                DetailsRow(station: station)
                            }
                        }
                    }
                }

                VStack {
                    Spacer()
                    GADBannerViewController(adUnitID: getEnv("AdUnitIdDetailsListFooter")!)
                        .frame(width: kGADAdSizeBanner.size.width, height: kGADAdSizeBanner.size.height)
                }
            }
            .navigationBarTitle("Details")
        }
    }

    init(stationGroups: StationGroups = [], searchText: String = "") {
        self.stationGroups = stationGroups
        self.searchText = searchText
        loadStationsFromJSON()
    }

    private mutating func loadStationsFromJSON() {
        DataManager.getDataFromFileWithSuccess { file in
            do {
                let data = try JSONDecoder().decode([String: StationGroups].self, from: file!)
                self.stationGroups = data["stationGroups"]!
            } catch {
                print(error)
            }
        }
    }
}

struct DetailsListView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsListView()
    }
}
