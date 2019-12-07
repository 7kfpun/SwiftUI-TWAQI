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
        let lastHistoricalPollutant = self.viewModel.historicalPollutants.last ?? HistoricalPollutant(
            aqi: 0,
            pm25: 0,
            pm10: 0,
            no2: 0,
            so2: 0,
            co: 0,
            o3: 0,
            windDirection: 0,
            windSpeed: 0,
            publishTime: "--"
        )

        let airIndexTypeSelected = self.settings.airIndexTypeSelected
        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: airIndexTypeSelected,
            value: lastHistoricalPollutant.getValue(airIndexType: airIndexTypeSelected)
        )
        let publishTime = lastHistoricalPollutant.publishTime.toDate()?.toFormat("HH:mm") ?? ""

        return VStack {
            HStack {
                NavigationLink(
                    destination: CountryListView()) {
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
                            value: lastHistoricalPollutant.getValue(airIndexType: airIndexTypeSelected)
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
                    id: 1,
                    countryId: 1,
                    countryCode: "twn",
                    code: "Songshan",
                    lat: 25.050000,
                    lon: 121.578611,
                    imageUrl: "",
                    name: "Songshan",
                    nameLocal: "松山"
                )
            )
            .previewDevice("Apple Watch Series 4 - 44mm")
            .environmentObject(SettingsStore())

            ContentView(
                station: Station(
                    id: 1,
                    countryId: 1,
                    countryCode: "twn",
                    code: "Songshan",
                    lat: 25.050000,
                    lon: 121.578611,
                    imageUrl: "",
                    name: "Songshan",
                    nameLocal: "松山"
                )
            )
            .previewDevice("Apple Watch Series 2 - 38mm")
            .environmentObject(SettingsStore())
        }
    }
}
