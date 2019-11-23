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

    @State private var showAqi = true

    var airIndexTypes: AirIndexTypes = AirIndexTypes.aqi
    var value: Double = 120

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
        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: airIndexTypes,
            value: lastHistoryPollutant.aqi
        )

        return VStack {
            HStack {
                NavigationLink(
                    destination: StationListView()) {
                        Text(Locale.isChinese ? settings.closestStation.nameLocal : settings.closestStation.name)
                }

                Button(action: {
                    self.showAqi.toggle()
                }) {
                    if showAqi {
                        VStack {
                            Text("AQI")
                                .font(.system(size: 9))
                                .multilineTextAlignment(.center)

                            LabelView(
                                airIndexTypes: AirIndexTypes.aqi,
                                value: lastHistoryPollutant.aqi
                            )
                        }
                    } else {
                        VStack {
                            Text("PM2.5")
                                .font(.system(size: 9))
                                .multilineTextAlignment(.center)

                            LabelView(
                                airIndexTypes: AirIndexTypes.pm25,
                                value: lastHistoryPollutant.pm25
                            )
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
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

                Text(lastHistoryPollutant.publishTime)
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
