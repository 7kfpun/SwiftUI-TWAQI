//
//  LabelView.swift
//  TWAQI
//
//  Created by kf on 22/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct LabelView: View {
    var airIndexTypes: AirIndexTypes
    var value: Double
    
    var body: some View {
        let text = value.format(f: airIndexTypes.getFormat())

        return Text(text)
            .foregroundColor(
                Color(AirStatuses.checkAirStatus(
                    airIndexType: airIndexTypes,
                    value: value
                ).getForegroundColor())
            )
            .fontWeight(.thin)
            .frame(minWidth: 25)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Color(AirStatuses.checkAirStatus(
                    airIndexType: airIndexTypes,
                    value: value
                ).getColor())
            )
            .cornerRadius(8)
    }
}

struct LabelView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LabelView(
                airIndexTypes: AirIndexTypes.aqi,
                value: 12
            )

            LabelView(
                airIndexTypes: AirIndexTypes.aqi,
                value: 55
            )

            LabelView(
                airIndexTypes: AirIndexTypes.aqi,
                value: 120
            )

            LabelView(
                airIndexTypes: AirIndexTypes.o3,
                value: 12.3
            )

            LabelView(
                airIndexTypes: AirIndexTypes.o3,
                value: 121.3
            )
        }
        .previewLayout(.fixed(width: 100, height: 100))
    }
}
