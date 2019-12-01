//
//  DetailsGroup.swift
//  TWAQI
//
//  Created by kf on 30/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsGroup: View {
    @State var isOpen = false
    var stationGroup: StationGroup

    var body: some View {
        VStack {
            Button(action: {
                self.isOpen.toggle()
                TrackingManager.logEvent(eventName: "toggle_history_group", parameters: [
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

                    if isOpen {
                        Image(systemName: "chevron.down")
                            .foregroundColor(Color.primary)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(Color.primary)
                    }
                }
                .padding(.horizontal)
            }

            if isOpen {
                ForEach(stationGroup.stations, id: \.self) {station in
                    DetailsRow(station: station)
                }
            }

            Divider()
                .padding(.vertical, 0)
                .padding(.leading, 15)
        }
    }

    init(stationGroup: StationGroup) {
        self.stationGroup = stationGroup
    }
}

struct DetailsGroup_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsGroup(stationGroup: StationGroup(name: "Lianjiang County", nameLocal: "連江縣", stations: [
                Station(name: "Lianjiang", nameLocal: "馬祖", lat: 26.160469, lon: 119.949875),
            ]))
            DetailsGroup(stationGroup: StationGroup(name: "Taipei City", nameLocal: "臺北市", stations: [
                Station(name: "Yangming", nameLocal: "陽明", lat: 25.182722, lon: 121.529583),
                Station(name: "Songshan", nameLocal: "松山", lat: 25.050000, lon: 121.578611),
            ]))
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
