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
        NavigationLink(destination: DetailsView(station: station)) {
            HStack {
                Text(station.name)
                    .foregroundColor(Color.black)
                    .fontWeight(.light)
                    .padding(.vertical, 10)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(Color.gray)
            }
            .padding(.horizontal)
        }
    }
}

struct DetailsRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsRow(station: Station(name: "Yangming", localName: "陽明", lon: 121.529583, lat: 25.182722))
            DetailsRow(station: Station(name: "Songshan", localName: "松山", lon: 121.578611, lat: 25.050000))
        }
        .previewLayout(.fixed(width: 300, height: 100))
    }
}
