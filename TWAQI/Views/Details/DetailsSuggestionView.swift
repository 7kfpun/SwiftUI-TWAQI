//
//  DetailsSuggestionView.swift
//  TWAQI
//
//  Created by kf on 14/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsSuggestionView: View {
    var lastPollutant: HistoricalPollutant

    var body: some View {
        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: AirIndexTypes.aqi,
            value: Double(self.lastPollutant.aqi)
        )

        return GeometryReader { geometry in
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

                    Image("status_\(airStatus)")
                        .resizable()
                        .frame(width: 65, height: 65)
                        .padding(.top, 10)

                    Spacer()

                    Text(airStatus.toString())
                        .foregroundColor(Color(airStatus.getForegroundColor()))
                        .font(.footnote)
                        .fontWeight(.regular)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 3)
                        .padding(.horizontal)
                        .lineLimit(2)
                        .background(Color(airStatus.getColor()))
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

                    Text(airStatus.getGeneralPublicGuidance())
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

                    Text(airStatus.getSensitivePublicGuidance())
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

    init(lastPollutant: HistoricalPollutant) {
        self.lastPollutant = lastPollutant
    }
}

struct DetailsSuggestionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsSuggestionView(lastPollutant: HistoricalPollutant(
                aqi: 20.0,
                pm25: 15.1,
                pm10: 26.0,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39.0,
                windDirection: 39.0,
                windSpeed: 2.1,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoricalPollutant(
                aqi: 61.4,
                pm25: 15.4,
                pm10: 26.4,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39.4,
                windDirection: 39.0,
                windSpeed: 2.1,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoricalPollutant(
                aqi: 141.0,
                pm25: 15.2,
                pm10: 26.3,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39.0,
                windDirection: 39.0,
                windSpeed: 2.1,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoricalPollutant(
                aqi: 180.0,
                pm25: 15.2,
                pm10: 26.3,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39.0,
                windDirection: 39.0,
                windSpeed: 2.1,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoricalPollutant(
                aqi: 300.0,
                pm25: 15.2,
                pm10: 26.3,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39.0,
                windDirection: 39.0,
                windSpeed: 2.1,
                publishTime: "2019-10-13T22:00:00"
            ))

            DetailsSuggestionView(lastPollutant: HistoricalPollutant(
                aqi: 500.0,
                pm25: 15,
                pm10: 26,
                no2: 6.7,
                so2: 2.3,
                co: 0.25,
                o3: 39,
                windDirection: 39.0,
                windSpeed: 2.1,
                publishTime: "2019-10-13T22:00:00"
            ))
        }
        .previewLayout(.sizeThatFits)
    }
}
