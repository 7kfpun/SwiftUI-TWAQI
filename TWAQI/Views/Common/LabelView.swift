//
//  LabelView.swift
//  TWAQI
//
//  Created by kf on 22/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct LabelView: View {
    var airIndexTypes: Constants.AirIndexTypes
    var value: Int
    
    var body: some View {
        Text("\(value)")
            .foregroundColor(Color(airIndexTypes.getAirStatus(value: value).getForegroundColor()))
            .fontWeight(.thin)
            .padding(6)
            .background(Color(airIndexTypes.getAirStatus(value: value).getColor()))
            .cornerRadius(8)
    }
}

struct LabelView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LabelView(
                airIndexTypes: Constants.AirIndexTypes.aqi,
                value: 12
            )

            LabelView(
                airIndexTypes: Constants.AirIndexTypes.aqi,
                value: 120
            )
        }
        .previewLayout(.fixed(width: 100, height: 100))
    }
}