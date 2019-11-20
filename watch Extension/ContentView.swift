//
//  ContentView.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var viewModel: ContentViewModel

    var airIndexTypes: AirIndexTypes = AirIndexTypes.aqi
    var value: Double = 120

    var body: some View {
        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: airIndexTypes,
            value: self.viewModel.historyPollutants.first?.aqi ?? 0
        )

        return VStack {
            HStack {
                NavigationLink(
                    destination: StationListView()) {
                        Text(Locale.isChinese ? settings.closestStation.nameLocal : settings.closestStation.name)
                }

                VStack {
                    Text("AQI")
                        .font(.system(size: 10))
                        .multilineTextAlignment(.center)

                    LabelView(
                        airIndexTypes: AirIndexTypes.aqi,
                        value: self.viewModel.historyPollutants.first?.aqi ?? 0
                    )
                }
            }

            Button(action: getData) {
                Spacer()

                Image("status_\(airStatus)")
                    .resizable()
                    .frame(width: 50, height: 50)

                Spacer()

                Text(airStatus.toString())
                    .font(.footnote)
                    .multilineTextAlignment(.center)

                Text(self.viewModel.historyPollutants.first?.publishTime ?? "-")
                    .fontWeight(.light)
                    .font(.system(size: 10))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .onAppear(perform: getData)
    }

    init(station: Station) {
        self.viewModel = ContentViewModel(station: station)
    }

    private func getData() {
        self.viewModel.station = settings.closestStation
        self.viewModel.getData()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(
                    station: Station(
                        name: "Matsu",
                        nameLocal: "馬祖",
                        lon: 119.949875,
                        lat: 26.160469
                    )
                )
                .previewDevice("Apple Watch Series 4 - 44mm")
                .environmentObject(SettingsStore())

            ContentView(
                    station: Station(
                        name: "Matsu",
                        nameLocal: "馬祖",
                        lon: 119.949875,
                        lat: 26.160469
                    )
                )
                .previewDevice("Apple Watch Series 2 - 38mm")
                .environmentObject(SettingsStore())
        }
    }
}
