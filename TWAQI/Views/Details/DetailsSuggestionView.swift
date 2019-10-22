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
                    Text("AQI")
                        .fontWeight(.regular)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black, lineWidth: 1)
                        )

                    Spacer()

                    Text("\(self.lastPollutant.aqi)")
                        .font(.largeTitle)

                    Spacer()

                    Text(Constants.AirIndexTypes.aqi.getAirStatus(value: self.lastPollutant.aqi).toString())
                        .fontWeight(.thin)
                }
                .frame(width: geometry.size.width / 3)

                VStack(alignment: .leading) {
                    Text("General public")
                        .fontWeight(.regular)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black, lineWidth: 1)
                        )

                    Text(Constants.AirIndexTypes.aqi.getAirStatus(value: self.lastPollutant.aqi).getGeneralPublicGuidance())
                        .font(.body)
                        .fontWeight(.thin)
                        .padding(.top, 6)

                    Spacer()

                    Text("Sensitive group")
                        .fontWeight(.regular)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black, lineWidth: 1)
                        )

                    Text(Constants.AirIndexTypes.aqi.getAirStatus(value: self.lastPollutant.aqi).getSensitivePublicGuidance())
                        .font(.body)
                        .fontWeight(.thin)
                        .padding(.top, 6
                    )
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
    }
}
