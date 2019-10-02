//
//  IndexSelector.swift
//  TWAQI
//
//  Created by kf on 1/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct IndexSelector: View {
    let indexes = [
        Index(key: "AQI", name: "AQI", unit: ""),
        Index(key: "PM2_5", name: "PM2.5", unit: "μg/m3"),
        Index(key: "PM10", name: "PM10", unit: "μg/m3"),
        Index(key: "O3", name: "O3", unit: "ppb"),
        Index(key: "CO", name: "CO", unit: "ppm"),
        Index(key: "SO2", name: "SO2", unit: "ppb"),
        Index(key: "NO2", name: "NO2", unit: "ppb")
    ]

    @State private var selectedIndex = "AQI"

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(indexes, id: \.key) {index in
                    Button(action: {
                        self.selectedIndex = index.key
                    }) {
                        if self.selectedIndex == index.key {
                            Text(index.name)
                                .fontWeight(.regular)
                                .padding(.vertical)
                                .frame(width: 55)
                                .padding(.horizontal)
                                .background(Color.white)
                                .cornerRadius(40)
                        } else {
                            Text(index.name)
                                .foregroundColor(Color.black)
                                .fontWeight(.regular)
                                .padding(.vertical)
                                .frame(width: 55)
                                .padding(.horizontal)
                                .background(Color.white)
                                .cornerRadius(40)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct IndexSelector_Previews: PreviewProvider {
    static var previews: some View {
        IndexSelector()
            .previewLayout(.fixed(width: 600, height: 100))
    }
}
