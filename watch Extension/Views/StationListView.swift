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
    @ObservedObject var viewModel: StationListViewModel

    let defaults = UserDefaults.standard

    var country: Country
    var stations: Stations

    var body: some View {
        VStack {
            List {
                ForEach(self.viewModel.stations, id: \.self) {station in
                    Button(action: {
                        print(station.nameLocal)
                        self.defaults.setStruct(station, forKey: "closestStationNew")
                        ComplicationManager.reloadComplications()
                        self.mode.wrappedValue.dismiss()
                    }) {
                        Text(Locale.isChinese ? station.nameLocal : station.name)
                    }
                }
            }
        }
        .onAppear {
            self.getData()
        }
    }

    init(country: Country, stations: Stations = []) {
        self.country = country
        self.stations = stations
        self.viewModel = StationListViewModel(country: country)
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct StationListView_Previews: PreviewProvider {
    static var previews: some View {
        StationListView(
            country: Country(
                id: 0,
                code: "twn",
                lat: 12,
                lon: 123.1,
                zoom: 12,
                name: "Taiwan",
                nameLocal: "台灣"
            ),
            stations: [
                Station(
                    id: 0,
                    countryId: 1,
                    countryCode: "twn",
                    code: "Yangming",
                    lat: 25.182722,
                    lon: 121.529583,
                    imageUrl: "",
                    name: "Yangming",
                    nameLocal: "陽明"
                ),
                Station(
                    id: 1,
                    countryId: 1,
                    countryCode: "twn",
                    code: "Songshan",
                    lat: 25.050000,
                    lon: 121.578611,
                    imageUrl: "",
                    name: "Songshan",
                    nameLocal: "松山"
                ),
            ]
        )
    }
}
