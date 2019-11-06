//
//  DetailsSuggestionView.swift
//  TWAQI
//
//  Created by kf on 14/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsSuggestionView: View {
    var lastPollutant: HistoryPollutant

    var body: some View {
        GeometryReader { geometry in
            HStack {
                VStack {
                    Text("AQI \(Int(self.lastPollutant.aqi))")
                        .font(.callout)
                        .fontWeight(.regular)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary, lineWidth: 0.5)
                        )

                    Spacer()

                    Image("status_good")
                        .resizable()
                        .frame(width: 65, height: 65)

                    Text(
                        AirStatuses.checkAirStatus(
                            airIndexType: AirIndexTypes.aqi,
                            value: Double(self.lastPollutant.aqi)
                        ).toString()
                    )
                    .foregroundColor(
                        Color(AirStatuses.checkAirStatus(
                            airIndexType: AirIndexTypes.aqi,
                            value: Double(self.lastPollutant.aqi)
                        ).getForegroundColor())
                    )
                    .font(.footnote)
                    .fontWeight(.regular)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 3)
                    .padding(.horizontal)
                    .lineLimit(2)
                    .background(
                        Color(AirStatuses.checkAirStatus(
                            airIndexType: AirIndexTypes.aqi,
                            value: Double(self.lastPollutant.aqi)
                        ).getColor())
                    )
                    .cornerRadius(6)
                }
                .frame(width: geometry.size.width / 3)

                VStack(alignment: .leading) {
                    Text("Details.general_public")
                        .font(.callout)
                        .fontWeight(.regular)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary, lineWidth: 0.5)
                        )

                    Text(
                        AirStatuses.checkAirStatus(
                            airIndexType: AirIndexTypes.aqi,
                            value: Double(self.lastPollutant.aqi)
                        ).getGeneralPublicGuidance()
                    )
                    .font(.footnote)
                    .fontWeight(.thin)
                    .padding(.top, 6)

                    Spacer()

                    Text("Details.sensitive_group")
                        .font(.callout)
                        .fontWeight(.regular)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary, lineWidth: 0.5)
                        )

                    Text(
                        AirStatuses.checkAirStatus(
                            airIndexType: AirIndexTypes.aqi,
                            value: Double(self.lastPollutant.aqi)
                        ).getSensitivePublicGuidance()
                    )
                    .font(.footnote)
                    .fontWeight(.thin)
                    .padding(.top, 6)
                }
                .frame(width: geometry.size.width * 2 / 3)
            }
        }
        .frame(height: 150)
        .padding()
    }

    init(lastPollutant: HistoryPollutant) {
        self.lastPollutant = lastPollutant
    }
}

struct DetailsSuggestionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsSuggestionView(lastPollutant: HistoryPollutant(
                stationId: 96,
                aqi: 20,
                pm25: 15,
                pm10: 26,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoryPollutant(
                stationId: 96,
                aqi: 61,
                pm25: 15,
                pm10: 26,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoryPollutant(
                stationId: 96,
                aqi: 141,
                pm25: 15,
                pm10: 26,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoryPollutant(
                stationId: 96,
                aqi: 180,
                pm25: 15,
                pm10: 26,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoryPollutant(
                stationId: 96,
                aqi: 300,
                pm25: 15,
                pm10: 26,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoryPollutant(
                stationId: 96,
                aqi: 500,
                pm25: 15,
                pm10: 26,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39,
                publishTime: "2019-10-13T22:00:00"
            ))
        }
        .previewLayout(.sizeThatFits)
    }
}
