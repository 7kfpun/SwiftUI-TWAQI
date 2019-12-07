//
//  DetailsHistoryView.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsHistoryView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    var historicalPollutants: HistoricalPollutants

    var body: some View {
        let historicalPollutantsMap: [AirIndexTypes: [Double]] = [
            AirIndexTypes.aqi: historicalPollutants.map({ $0.aqi }),
            AirIndexTypes.pm25: historicalPollutants.map({ $0.pm25 }),
            AirIndexTypes.pm10: historicalPollutants.map({ $0.pm10 }),
            AirIndexTypes.o3: historicalPollutants.map({ $0.o3 }),
            AirIndexTypes.co: historicalPollutants.map({ $0.co }),
            AirIndexTypes.so2: historicalPollutants.map({ $0.so2 }),
            AirIndexTypes.no2: historicalPollutants.map({ $0.no2 }),
        ]

        let bars: [Bar] = historicalPollutantsMap[settings.airIndexTypeSelected]!.map {
            Bar(
                value: $0,
                color: Color(AirStatuses.checkAirStatus(
                    airIndexType: settings.airIndexTypeSelected,
                    value: $0
                ).getColor())
            )
        }

        return VStack {
            Picker(
                selection: $settings.airIndexTypeSelected,
                label: Text("Air Index Type").fontWeight(.light)
            ) {
                ForEach(AirIndexTypes.allCases, id: \.self) {
                    Text($0.toString())
                        .tag($0)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom)

            if !bars.isEmpty {
                HStack {
                    VStack {
                        LabelView(
                            airIndexTypes: settings.airIndexTypeSelected,
                            value: historicalPollutantsMap[settings.airIndexTypeSelected]?.last ?? 0
                        )

                        Spacer()

                        Text(self.settings.airIndexTypeSelected.toString())
                            .font(.caption)
                            .fontWeight(.regular)
                        Text(self.settings.airIndexTypeSelected.getUnit())
                            .font(.caption)
                            .fontWeight(.thin)
                    }
                    .padding()

                    VStack {
                        BarsView(bars: bars)
                        HStack {
                            VStack {
                                Text(self.historicalPollutants.first?.publishTime.toDate()?.toFormat("HH:mm") ?? "")
                                    .font(.caption)
                                    .fontWeight(.thin)

                                Text(self.historicalPollutants.first?.publishTime.toDate()?.toFormat("MM/dd") ?? "")
                                    .font(.caption)
                                    .fontWeight(.thin)
                            }

                            Spacer()

                            VStack {
                                Text(self.historicalPollutants.last?.publishTime.toDate()?.toFormat("HH:mm") ?? "")
                                    .font(.caption)
                                    .fontWeight(.thin)

                                Text(self.historicalPollutants.last?.publishTime.toDate()?.toFormat("MM/dd") ?? "")
                                    .font(.caption)
                                    .fontWeight(.thin)
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top) {
                Text(settings.airIndexTypeSelected.toString())
                    .fontWeight(.light)
                    .font(.caption)

                Text("-")
                    .fontWeight(.light)
                    .font(.caption)

                Text(settings.airIndexTypeSelected.getDescription())
                    .fontWeight(.light)
                    .font(.caption)

                Spacer()
            }
            .padding(.leading, 5)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
    }

    init(historicalPollutants: HistoricalPollutants) {
        self.historicalPollutants = historicalPollutants
    }
}

//struct DetailsHistoryView_Previews: PreviewProvider {
//    static var previews: some View {
//        DetailsHistoryView(historicalPollutants: [
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 40,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T01:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 20,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T02:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 11,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T03:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 32,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T04:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 40,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T05:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 20,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T06:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 11,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T07:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 14,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T08:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 14,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T09:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 32,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T10:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 40,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T11:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 20,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T12:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 11,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T13:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 14,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T14:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 14,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T14:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 43,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T15:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 32,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T15:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 30,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T16:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 22,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T16:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 25,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T17:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 20,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T17:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 30,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T18:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 56,
//                aqi: 61,
//                pm25: 25,
//                pm10: 26,
//                no2: 5.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T19:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 51,
//                pm25: 26,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T20:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 90,
//                aqi: 61,
//                pm25: 11,
//                pm10: 26,
//                no2: 6.7,
//                so2: 2.3,
//                co: 0.25,
//                o3: 39,
//                publishTime: "2019-10-13T21:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 96,
//                aqi: 51,
//                pm25: 22,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T22:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 96,
//                aqi: 51,
//                pm25: 22,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-13T23:00:00"
//            ),
//            HistoricalPollutant(
//                stationId: 80,
//                aqi: 64,
//                pm25: 30,
//                pm10: 36,
//                no2: 6.9,
//                so2: 1.3,
//                co: 0.15,
//                o3: 30,
//                publishTime: "2019-10-14T00:00:00"
//            ),
//        ])
//        .environmentObject(SettingsStore())
//    }
//}
