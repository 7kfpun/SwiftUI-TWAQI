//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsView: View {
    var station: Station
    private var name: String
    private var localName: String

    var body: some View {
        VStack {
            Text(self.name)
            Text(self.localName)
        }
    }

    init(station: Station) {
        self.station = station
        self.name = station.name
        self.localName = station.localName
    }
}

struct DetailsView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsView(station: Station(name: "Lianjiang", localName: "馬祖", lon: 119.949875, lat: 26.160469))
    }
}
