//
//  SettingsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsRow: View {
    @State var isNotificationEnabled = false
    @State private var min: Double = 30
    @State private var max: Double = 120

    var station: Station

    var body: some View {
        VStack {
            Toggle(isOn: $isNotificationEnabled) {
                Text(station.name)
                    .fontWeight(.light)
                    .padding(.vertical, 15)
            }

            if isNotificationEnabled {
                HStack {
                    Text("Pollution therhold")
                        .fontWeight(.light)
                    Spacer()
                    Text("\(max)")
                }

                Slider(value: $max, in: 0...500, step: 1)

                HStack {
                    Text("Cleanliness therhold")
                        .fontWeight(.light)
                    Spacer()
                    Text("\(min)")
                }

                Slider(value: $min, in: 0...500, step: 1)
            }
        }
    }

    init(station: Station) {
        self.station = station
    }
}

struct SettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsRow(station: Station(name: "Yangming", localName: "陽明", lon: 121.529583, lat: 25.182722))
            SettingsRow(station: Station(name: "Songshan", localName: "松山", lon: 121.578611, lat: 25.050000))
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
