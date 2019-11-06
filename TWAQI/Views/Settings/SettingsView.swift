//
//  SettingsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    TextField("Settings.search", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()

                    if searchText.isEmpty {
                        ForEach(self.viewModel.stationGroups, id: \.self) {stationGroup in
                            SettingsGroup(stationGroup: stationGroup)
                        }
                    } else {
                        ForEach(self.viewModel.stationGroups, id: \.self) {stationGroup in
                            ForEach(
                                stationGroup.stations.filter {$0.name.hasPrefix(self.searchText) || self.searchText.isEmpty}, id: \.self
                            ) {station in
                                SettingsRow(station: station)
                            }
                        }
                    }
                }
                .padding(.bottom, 50)

                AdBanner(adUnitID: getEnv("AdUnitIdSettingsFooter")!)
            }
            .navigationBarTitle("Settings.notification")
        }.onAppear(perform: loadData)
    }
    
    private func loadData() {
        self.viewModel.loadStationsFromJSON()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: .init())
    }
}
