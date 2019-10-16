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
                    Text("\(self.lastPollutant.aqi)")
                    Text("Good")
                }
                .frame(width: geometry.size.width / 3, height: 140)

                VStack {
                    Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
                    Text("Hello, World!")

                    Spacer()

                    Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
                    Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
                }
                .frame(width: geometry.size.width * 2 / 3, height: 140)
            }
        }
        .frame(height: 150)
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
