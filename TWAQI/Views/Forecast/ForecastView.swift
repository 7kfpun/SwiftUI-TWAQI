//
//  ForecastView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct ForecastView: View {
    @ObservedObject var viewModel: ForecastViewModel

    @State private var isForecastNotificationEnabled = true
    @State private var forecastType = 0

    var body: some View {
        let groupedByAreas = Dictionary(grouping: viewModel.forecastAreas) { $0.area }
        let areaGroups: [String] = ["北部", "竹苗", "中部", "雲嘉南", "高屏", "宜蘭", "花東", "馬祖", "金門", "澎湖"]

        return NavigationView {
            ScrollView {
                VStack {
                    Toggle(isOn: $isForecastNotificationEnabled) {
                        Text("Forecast Notification (daily)")
                            .bold()
                    }

                    Indicator()
                        .frame(height: 90)

                    Picker(selection: $forecastType, label: Text("Forecast view?")) {
                        Text("3 Days").tag(0)
                        Text("Details").tag(1)
                    }.pickerStyle(SegmentedPickerStyle())

                    if forecastType == 0 {
                        HStack {
                            ForEach(groupedByAreas["北部"] ?? [], id: \.self) {area in
                                Text(area.forecastDate)
                            }
                        }

                        ForEach(areaGroups, id: \.self) {areaGroup in
                            HStack {
                                Text(areaGroup)
                                ForEach(groupedByAreas[areaGroup] ?? [], id: \.self) {area in
                                    Text(area.aqi)
                                }
                            }
                        }
                    }

                    if forecastType == 1 {
                        Text(viewModel.forecastDetail)
                    }
                }
                .padding()
            }
            .navigationBarTitle("Forecast")
        }.onAppear(perform: getData)
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct ForecastView_Previews: PreviewProvider {
    static var previews: some View {
        ForecastView(viewModel: .init())
    }
}
