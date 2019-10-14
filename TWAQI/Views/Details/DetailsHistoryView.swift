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
    @ObservedObject var viewModel = DetailsHistoryViewModel()

    var station: Station

    @State private var viewType = 0

    var body: some View {
        let data = viewModel.historytPollutants.map({ (historytPollutant) -> Int in
            return historytPollutant.aqi
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
            .onAppear(perform: getData)

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

    init(station: Station) {
        self.station = station
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct DetailsHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsHistoryView(station: Station(
            name: "Matsu",
            localName: "馬祖",
            lon: 119.949875,
            lat: 26.160469,
            imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
        ))
    }
}
