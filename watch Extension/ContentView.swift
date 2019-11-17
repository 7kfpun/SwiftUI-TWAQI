//
//  ContentView.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack {
            HStack {
                NavigationLink(
                    destination: StationListView()) {
                        Text(settings.closestStationName)
                }

                Spacer()

                LabelView(
                    airIndexTypes: AirIndexTypes.aqi,
                    value: 120
                )
            }

            Spacer()

            Image("status_good")
                .resizable()
                .frame(width: 50, height: 50)

            Spacer()

            Text("對敏感族群不良")
                .font(.footnote)

            Text("2019/10/22 10:30")
                .fontWeight(.light)
                .font(.footnote)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewDevice("Apple Watch Series 4 - 44mm")
                .environmentObject(SettingsStore())

            ContentView()
                .previewDevice("Apple Watch Series 2 - 38mm")
                .environmentObject(SettingsStore())
        }
    }
}
