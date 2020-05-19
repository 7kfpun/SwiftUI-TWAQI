//
//  DetailsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsRow: View {
    var station: Station

    var body: some View {
        NavigationLink(destination: DetailsView(stationId: station.id).environmentObject(SettingsStore())) {
            HStack {
                Text(Locale.isChinese ? station.nameLocal : station.name)
                    .foregroundColor(Color.primary)
                    .fontWeight(.light)
                    .padding(.vertical, 10)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(Color.secondary)
            }
            .padding(.horizontal)
        }
    }
}

struct DetailsRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsRow(station: Station(
                id: 0,
                countryId: 1,
                countryCode: "twn",
                code: "Yangming",
                lat: 25.182722,
                lon: 121.529583,
                imageUrl: "",
                name: "Yangming",
                nameLocal: "陽明"
            ))
            DetailsRow(station: Station(
                id: 1,
                countryId: 1,
                countryCode: "twn",
                code: "Songshan",
                lat: 25.050000,
                lon: 121.578611,
                imageUrl: "",
                name: "Songshan",
                nameLocal: "松山"
            ))
        }
        .previewLayout(.fixed(width: 300, height: 100))
    }
}
