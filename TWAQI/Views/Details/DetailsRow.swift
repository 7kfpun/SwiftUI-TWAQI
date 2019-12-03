//
//  DetailsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsRow: View {
    var station: NewStation

    var body: some View {
        NavigationLink(destination: DetailsView(stationId: station.id)) {
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

//struct DetailsRow_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            DetailsRow(station: Station(name: "Yangming", nameLocal: "陽明", lat: 25.182722, lon: 121.529583))
//            DetailsRow(station: Station(name: "Songshan", nameLocal: "松山", lat: 25.050000, lon: 121.578611))
//        }
//        .previewLayout(.fixed(width: 300, height: 100))
//    }
//}
