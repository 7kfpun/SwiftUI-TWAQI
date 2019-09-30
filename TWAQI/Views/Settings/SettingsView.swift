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
    @State private var isDnDEnable = true

    let stationGroups = [
        StationGroup(name: "Lianjiang County", localName: "連江縣", stations: [
            Station(name: "Lianjiang", localName: "馬祖", lon: 119.949875, lat: 26.160469)
        ]),
        StationGroup(name: "Taipei City", localName: "臺北市", stations: [
            Station(name: "Yangming", localName: "陽明", lon: 121.529583, lat: 25.182722),
            Station(name: "Songshan", localName: "松山", lon: 121.578611, lat: 25.050000)
        ]),
        StationGroup(name: "New Taipei City", localName: "新北市", stations: []),
        StationGroup(name: "Keelung City", localName: "基隆市", stations: []),
        StationGroup(name: "Taoyuan City", localName: "桃園市", stations: []),
        StationGroup(name: "Hsinchu County", localName: "新竹縣", stations: []),
        StationGroup(name: "Hsinchu City", localName: "新竹市", stations: []),
        StationGroup(name: "Ilan County", localName: "宜蘭縣", stations: []),
        StationGroup(name: "Miaoli County", localName: "苗栗縣", stations: []),
        StationGroup(name: "Kinmen County", localName: "金門縣", stations: []),
        StationGroup(name: "Taichung City", localName: "臺中市", stations: []),
        StationGroup(name: "Changhua County", localName: "彰化縣", stations: []),
        StationGroup(name: "Hualien County", localName: "花蓮縣", stations: []),
        StationGroup(name: "Nantou County", localName: "南投縣", stations: []),
        StationGroup(name: "Yunlin County", localName: "雲林縣", stations: []),
        StationGroup(name: "Penghu County", localName: "澎湖縣", stations: []),
        StationGroup(name: "Chiayi County", localName: "嘉義縣", stations: []),
        StationGroup(name: "Chiayi City", localName: "嘉義市", stations: []),
        StationGroup(name: "Tainan City", localName: "臺南市", stations: []),
        StationGroup(name: "Taitung County", localName: "臺東縣", stations: []),
        StationGroup(name: "Kaohsiung City", localName: "高雄市", stations: []),
        StationGroup(name: "Pingtung County", localName: "屏東縣", stations: [])
    ]

    var body: some View {
        NavigationView {
            VStack {
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                // DnD
                VStack {
                    Toggle(isOn: $isDnDEnable) {
                        Text("Do not disturb")
                            .bold()
                    }
                    .padding(.horizontal)

                    Divider()

                    HStack {
                        Text("Start Date")
                        Spacer()
                        Text("10:00 PM")
                    }
                    .padding(.horizontal)

                    HStack {
                        Text("End Date")
                        Spacer()
                        Text("8:30 AM")
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .background(Color(0xEEEEEE))

                if searchText.isEmpty {
                    List {
                        ForEach(stationGroups, id: \.self) {stationGroup in
                            SettingsGroup(stationGroup: stationGroup)
                        }
                    }
                } else {
                    List {
                        ForEach(stationGroups, id: \.self) {stationGroup in
                            ForEach(stationGroup.stations.filter {$0.name.hasPrefix(self.searchText) || self.searchText.isEmpty}, id: \.self) {station in
                                SettingsRow(station: station)
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("Notification")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
