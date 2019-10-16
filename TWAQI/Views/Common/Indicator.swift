//
//  Indicator.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct IndexRange {
    var id: Int
    var type: String
    var status: String
    var color: UInt32
}

struct Indicator: View {
    let indexRanges = [
        IndexRange(
            id: 0,
            type: "AQI",
            status: "Good",
            color: 0x009866
        ),
        IndexRange(
            id: 1,
            type: "AQI",
            status: "Moderate",
            color: 0xFEDE33
        ),
        IndexRange(
            id: 2,
            type: "AQI",
            status: "Unhealthy for sensitive groups",
            color: 0xFE9833
        ),
        IndexRange(
            id: 3,
            type: "AQI",
            status: "Unhealthy",
            color: 0xCC0033
        ),
        IndexRange(
            id: 4,
            type: "AQI",
            status: "Very unhealthy",
            color: 0x660098
        ),
        IndexRange(
            id: 5,
            type: "AQI",
            status: "Hazardous",
            color: 0x7E2200
        ),
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top) {
                ForEach(self.indexRanges, id: \.id) { indexRange in
                    VStack {
                        Rectangle()
                            .fill(Color(indexRange.color))
                            .frame(
                                width: (geometry.size.width - 80) / 6,
                                height: 6
                            )
                            .cornerRadius(10, antialiased: true)
                        Text(indexRange.status)
                            .font(.caption)
                            .fontWeight(.light)
                            .multilineTextAlignment(.center)
                    }
                    .padding(0)
                }
            }
        }
    }
}

struct Indicator_Previews: PreviewProvider {
    static var previews: some View {
        Indicator()
            .previewLayout(.fixed(width: 400, height: 100))
    }
}
