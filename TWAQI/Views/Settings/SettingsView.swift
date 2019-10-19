//
//  SettingsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @State private var searchText = ""

    var stationGroups: StationGroups

    var body: some View {
        NavigationView {
            ScrollView {
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                if searchText.isEmpty {
                    DnD()

                    ForEach(stationGroups, id: \.self) {stationGroup in
                        SettingsGroup(stationGroup: stationGroup)
                    }
                } else {
                    ForEach(stationGroups, id: \.self) {stationGroup in
                        ForEach(stationGroup.stations.filter {$0.name.hasPrefix(self.searchText) || self.searchText.isEmpty}, id: \.self) {station in
                            SettingsRow(station: station)
                        }
                    }
                }
            }
            .navigationBarTitle("Notification")
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

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
