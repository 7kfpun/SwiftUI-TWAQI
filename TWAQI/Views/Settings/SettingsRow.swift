//
//  SettingsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsRow: View {
    @State private var isPollutionNotificationEnabled: Bool = false
    @State private var isCleanlinessNotificationEnabled: Bool = false
    @State private var min: Double = 30
    @State private var max: Double = 120

    var station: Station

    var body: some View {
        VStack {
            HStack {
                Text(station.name)
                    .fontWeight(.regular)
                    .padding(.top, 15)
                Spacer()
            }

            // Pollution Notification
            Toggle(isOn: $isPollutionNotificationEnabled) {
                Text("Notice me when AQI is above")
                    .fontWeight(.thin)

                LabelView(
                    airIndexTypes: Constants.AirIndexTypes.aqi,
                    value: Int(max)
                )
            }

            if self.isPollutionNotificationEnabled {
                Slider(value: $max, in: 1...500, step: 1)
            }

            // Cleanliness Notification
            Toggle(isOn: $isCleanlinessNotificationEnabled) {
                Text("Notice me when AQI is below")
                    .fontWeight(.thin)

                LabelView(
                    airIndexTypes: Constants.AirIndexTypes.aqi,
                    value: Int(min)
                )
            }

            if self.isCleanlinessNotificationEnabled {
                Slider(value: $min, in: 1...500, step: 1)
            }
        }
        .padding(.horizontal)
    }

    init(station: Station) {
        self.station = station
    }
}

struct SettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsRow(station: Station(name: "Yangming", nameLocal: "陽明", lon: 121.529583, lat: 25.182722))
            SettingsRow(station: Station(name: "Songshan", nameLocal: "松山", lon: 121.578611, lat: 25.050000))
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
