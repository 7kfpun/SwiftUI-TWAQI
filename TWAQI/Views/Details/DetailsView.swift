//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct DetailsView: View {
    var station: Station

    var body: some View {
        ScrollView {
            VStack {
                if !self.station.imageUrl.isEmpty {
                    WebImage(url: URL(string: self.station.imageUrl))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                Indicator()

                DetailsHistoryView(station: self.station)
            }
        }
    }

    init(station: Station) {
        self.station = station
    }
}

struct DetailsView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsView(station: Station(
            name: "Matsu",
            localName: "馬祖",
            lon: 119.949875,
            lat: 26.160469,
            imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
        ))
    }
}
