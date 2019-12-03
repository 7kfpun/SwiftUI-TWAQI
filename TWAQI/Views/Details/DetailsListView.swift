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
                    TextField("DetailsList.search", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()

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

//                    if searchText.isEmpty {
//                        ForEach(stationGroups, id: \.self) {stationGroup in
//                            DetailsGroup(stationGroup: stationGroup)
//                        }
//                    } else {
//                        ForEach(stationGroups, id: \.self) {stationGroup in
//                            ForEach(
//                                stationGroup.stations.filter {
//                                    $0.name.localizedCaseInsensitiveContains(self.searchText)
//                                    || $0.nameLocal.localizedCaseInsensitiveContains(self.searchText)
//                                    || self.searchText.isEmpty
//                                }, id: \.self
//                            ) {station in
//                                DetailsRow(station: station)
//                            }
//                        }
//                    }

                    Spacer().frame(height: 50)
                }

                AdBannerView(adUnitID: getEnv("AdUnitIdDetailsListFooter")!)
            }
            .navigationBarTitle("DetailsList.details")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            self.getData()
        }
    }

    init() {
        self.viewModel = DetailsListViewModel()
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct DetailsListView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsListView()
    }
}
