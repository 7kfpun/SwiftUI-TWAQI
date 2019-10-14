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
    var historyPollutants: [HistoryPollutant]

    @State private var viewType = 0

    var body: some View {
        let data = self.historyPollutants.map({ (historyPollutant) -> Int in
            return historyPollutant.aqi
        })

        print("data", data)

        return VStack {
            Picker(selection: $viewType, label: Text("History Type")) {
                Text("AQI").tag(0)
                Text("PM2.5").tag(1)
                Text("PM10").tag(2)
                Text("O3").tag(3)
                Text("CO").tag(4)
                Text("SO2").tag(5)
                Text("NO2").tag(6)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom, 10)

            if !data.isEmpty {
                BarChartView(
                    data: data,
                    title: "123",
                    form: Form.large
                )
            }

            Text("AQI - Air quality index")
        }
        .padding(.horizontal, 10)
    }

    init(historyPollutants: [HistoryPollutant]) {
        self.historyPollutants = historyPollutants
    }
}

struct DetailsHistoryView_Previews: PreviewProvider {
    static var previews: some View {
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
            )
        ])
    }
}
