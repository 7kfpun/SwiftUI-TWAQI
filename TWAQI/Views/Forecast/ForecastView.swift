//
//  ForecastView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct ForecastView: View {
    @State private var isForecastNotificationEnabled = true
    @State private var forecastType = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading) {
                    Toggle(isOn: $isForecastNotificationEnabled) {
                        Text("Forecast Notification (daily)")
                            .bold()
                    }

                    Indicator()
                        .frame(height: 90)

                    Picker(selection: $forecastType, label: Text("Forecast view?")) {
                        Text("3 Days").tag(0)
                        Text("Details").tag(1)
                    }.pickerStyle(SegmentedPickerStyle())
                }
                .padding()
            }
            .navigationBarTitle("Forecast")
        }
    }
}

struct ForecastView_Previews: PreviewProvider {
    static var previews: some View {
        ForecastView()
    }
}
