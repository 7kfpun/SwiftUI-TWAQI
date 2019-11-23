//
//  StationListView.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct StationListView: View {
    @Environment(\.presentationMode) var mode: Binding<PresentationMode>

    var stationGroups: StationGroups

    var body: some View {
        let defaults = UserDefaults.standard

        return List {
            ForEach(stationGroups, id: \.self) {stationGroup in
                ForEach(stationGroup.stations, id: \.self) {station in
                    Button(action: {
                        print(station.nameLocal)
                        defaults.setStruct(station, forKey: "closestStation")
                        ComplicationManager.reloadComplications()
                        self.mode.wrappedValue.dismiss()
                    }) {
                        Text(Locale.isChinese ? station.nameLocal : station.name)
                    }
                }
            }
        }
    }

    init(stationGroups: StationGroups = []) {
        self.stationGroups = stationGroups
        loadStationsFromJSON()
    }

    private mutating func loadStationsFromJSON() {
        DataManager.getDataFromFileWithSuccess { file in
            do {
                let data = try JSONDecoder().decode([String: StationGroups].self, from: file!)
                self.stationGroups = data["stationGroups"]!
                print(self.stationGroups)
            } catch {
                print(error)
            }
        }
    }
}

struct StationListView_Previews: PreviewProvider {
    static var previews: some View {
        StationListView(
            stationGroups: [
                StationGroup(name: "Taipei City", nameLocal: "臺北市", stations: [
                    Station(name: "Yangming", nameLocal: "陽明", lon: 121.529583, lat: 25.182722),
                    Station(name: "Songshan", nameLocal: "松山", lon: 121.578611, lat: 25.050000),
                ]),
            ]
        )
    }
}
