//
//  DetailsGroup.swift
//  TWAQI
//
//  Created by kf on 30/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsGroup: View {
    @State var isOpen = true
    var stationGroup: StationGroup
    
    var body: some View {
        VStack {
            HStack {
                Text(stationGroup.name)
                    .bold()
                    .padding(.vertical, 15)
                    .foregroundColor(Color.black)
                Spacer()
                if isOpen {
                    Image(systemName: "chevron.down")
                        .foregroundColor(Color.black)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color.black)
                }
            }

            ForEach(stationGroup.stations, id: \.self) {station in
                DetailsRow(station: station)
            }
        }
    }

    init(stationGroup: StationGroup) {
        self.stationGroup = stationGroup
    }
}

struct DetailsGroup_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsGroup(stationGroup: StationGroup(name: "Lianjiang County", localName: "連江縣", stations: [
                Station(name: "Lianjiang", localName: "馬祖", lon: 119.949875, lat: 26.160469)
            ]))
            DetailsGroup(stationGroup: StationGroup(name: "Taipei City", localName: "臺北市", stations: [
                Station(name: "Yangming", localName: "陽明", lon: 121.529583, lat: 25.182722),
                Station(name: "Songshan", localName: "松山", lon: 121.578611, lat: 25.050000)
            ]))
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
