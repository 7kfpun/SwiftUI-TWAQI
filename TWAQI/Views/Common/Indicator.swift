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
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top) {
                ForEach(AirStatuses.getShowAllCases(), id: \.self) { airStatus in
                    VStack {
                        Rectangle()
                            .fill(Color(airStatus.getColor()))
                            .frame(
                                width: (geometry.size.width - 80) / 6,
                                height: 6
                            )
                            .cornerRadius(10, antialiased: true)
                        Text(airStatus.toString())
                            .font(.caption)
                            .fontWeight(.light)
                            .multilineTextAlignment(.center)
                    }
                    .padding(0)
                }
            }
        }
        .frame(height: 80)
    }
}

struct Indicator_Previews: PreviewProvider {
    static var previews: some View {
        Indicator()
            .previewLayout(.fixed(width: 600, height: 100))
    }
}
