//
//  ContentView.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftDate
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject var viewModel: ContentViewModel

    var airIndexTypes: AirIndexTypes = AirIndexTypes.aqi

    var body: some View {
        let lastHistoryPollutant = self.viewModel.historyPollutants.last ?? HistoryPollutant(
            stationId: 0,
            aqi: 0,
            pm25: 0,
            pm10: 0,
            no2: 0,
            so2: 0,
            co: 0,
            o3: 0,
            publishTime: "--"
        )

        let airIndexTypeSelected = self.settings.airIndexTypeSelected
        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: airIndexTypeSelected,
            value: lastHistoryPollutant.getValue(airIndexType: airIndexTypeSelected)
        )
        let publishTime = lastHistoryPollutant.publishTime.toDate()?.toFormat("HH:mm") ?? ""

        return VStack {
            HStack {
                NavigationLink(
                    destination: StationListView()) {
                        Text(Locale.isChinese ? settings.closestStation.nameLocal : settings.closestStation.name)
                }

                Button(action: {
                    if airIndexTypeSelected == AirIndexTypes.aqi {
                        self.settings.airIndexTypeSelected = AirIndexTypes.pm25
                    } else {
                        self.settings.airIndexTypeSelected = AirIndexTypes.aqi
                    }

                    ComplicationManager.reloadComplications()
                }) {
                    VStack {
                        Text(airIndexTypeSelected.toString())
                            .font(.system(size: 9))
                            .multilineTextAlignment(.center)

                        LabelView(
                            airIndexTypes: airIndexTypeSelected,
                            value: lastHistoryPollutant.getValue(airIndexType: airIndexTypeSelected)
                        )
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button(action: getData) {
                Spacer()

                Image(airStatus.getImage())
                    .resizable()
                    .frame(width: 50, height: 50)

                Spacer()

                if self.viewModel.isLoading {
                    Image(systemName: "arrow.2.circlepath")
                    Spacer()
                } else {
                    Text(airStatus.toString())
                        .font(.footnote)
                        .multilineTextAlignment(.center)

                    Text(publishTime)
                        .fontWeight(.light)
                        .font(.system(size: 12))
                }
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

        ComplicationManager.reloadComplications()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(
                station: Station(
                    name: "Matsu",
                    nameLocal: "馬祖",
                    lat: 26.160469,
                    lon: 119.949875
                )
            )
            .previewDevice("Apple Watch Series 4 - 44mm")
            .environmentObject(SettingsStore())

            ContentView(
                station: Station(
                    name: "Matsu",
                    nameLocal: "馬祖",
                    lat: 26.160469,
                    lon: 119.949875
                )
            )
            .previewDevice("Apple Watch Series 2 - 38mm")
            .environmentObject(SettingsStore())
        }
    }
}
