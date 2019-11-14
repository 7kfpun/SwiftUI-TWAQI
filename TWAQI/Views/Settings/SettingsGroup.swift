//
//  SettingsGroup.swift
//  TWAQI
//
//  Created by kf on 30/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsGroup: View {
    @State private var isOpen: Bool = false
    var stationGroup: StationGroup

    var body: some View {
        VStack {
            Button(action: {
                self.isOpen.toggle()
                TrackingManager.logEvent(eventName: "toggle_settings_group", parameters: [
                    "name": self.stationGroup.name,
                    "nameLocal": self.stationGroup.nameLocal,
                ])
            }) {
                HStack {
                    Text(Locale.isChinese ? stationGroup.nameLocal : stationGroup.name)
                        .bold()
                        .padding(.vertical, 10)
                        .foregroundColor(Color.primary)
                    Spacer()
                    if self.isOpen {
                        Image(systemName: "chevron.down")
                            .foregroundColor(Color.primary)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(Color.primary)
                    }
                }
                .padding(.horizontal)
            }

            if self.isOpen {
                ForEach(stationGroup.stations, id: \.self) {station in
                    SettingsRow(station: station)
                }
            }

            Divider()
                .padding(.vertical, 0)
                .padding(.leading, 15)
        }
    }
}

struct SettingsGroup_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsGroup(
                stationGroup: StationGroup(
                    name: "Lianjiang County",
                    nameLocal: "連江縣",
                    stations: [
                        Station(name: "Lianjiang", nameLocal: "馬祖", lon: 119.949875, lat: 26.160469),
                    ]
                )
            )
            SettingsGroup(
                stationGroup: StationGroup(
                    name: "Taipei City",
                    nameLocal: "臺北市",
                    stations: [
                        Station(name: "Yangming", nameLocal: "陽明", lon: 121.529583, lat: 25.182722),
                        Station(name: "Songshan", nameLocal: "松山", lon: 121.578611, lat: 25.050000),
                    ]
                )
            )
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
