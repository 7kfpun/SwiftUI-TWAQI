//
//  DetailsHistoryView.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI
import SwiftUICharts

struct DetailsHistoryView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    var historyPollutants: [HistoryPollutant]

    @State private var viewType = 0

    var body: some View {
        let data = self.historyPollutants.map({ (historyPollutant) -> Int in
            return historyPollutant.aqi
        })

        return VStack {
            Picker(
                selection: $settings.airIndexTypeSelected,
                label: Text("Air Index Type").fontWeight(.light)
            ) {
                ForEach(Constants.AirIndexTypes.allCases, id: \.self) {
                    Text($0.toString())
                        .tag($0)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom)

            if !data.isEmpty {
                BarChartView(
                    data: data,
                    title: "\(settings.airIndexTypeSelected.toString()) - \(data.last!)",
                    style: colorScheme == .light ? Styles.barChartStyleOrangeLight : Styles.barChartStyleOrangeDark,
                    form: Form.large
                )
            }

            HStack {
                Text("AQI - Air quality index")
                    .fontWeight(.light)
                Spacer()
            }
        }
        .padding(.horizontal, 10)
    }

    init(historyPollutants: [HistoryPollutant]) {
        self.historyPollutants = historyPollutants
    }
}

struct DetailsHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsHistoryView(historyPollutants: [
                HistoryPollutant(
                    stationId: 96,
                    aqi: 61,
                    pm25: 15,
                    pm10: 26,
                    no2: 6.7,
                    so2: 2.3,
                    co: 0.25,
                    o3: 39,
                    publishTime: "2019-10-13T22:00:00"
                ),
            ])
            .environmentObject(SettingsStore())
            DetailsHistoryView(historyPollutants: [
                HistoryPollutant(
                    stationId: 96,
                    aqi: 61,
                    pm25: 15,
                    pm10: 26,
                    no2: 6.7,
                    so2: 2.3,
                    co: 0.25,
                    o3: 39,
                    publishTime: "2019-10-13T22:00:00"
                ),
            ])
            .environmentObject(SettingsStore())
            .environment(\.colorScheme, .dark)
        }
    }
}
