//
//  SettingsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsRow: View {
    @ObservedObject var viewModel: SettingsRowViewModel

    var station: Station

    let TOO_SMALL_POLLUTION = 110.0
    let TOO_LARGE_CLEANLINESS = 30.0

    var body: some View {
        VStack {
            HStack {
                Text(Locale.isChinese ? station.nameLocal : station.name)
                    .fontWeight(.regular)
                    .padding(.top, 15)
                Spacer()
            }

            // Pollution Notification
            Toggle(isOn: $viewModel.stationSetting.isPollutionNotificationEnabled) {
                Text("Settings.notice_me_when_aqi_is_above")
                    .fontWeight(.thin)

                LabelView(
                    airIndexTypes: AirIndexTypes.aqi,
                    value: viewModel.stationSetting.pollutionTherhold
                )
            }

            if viewModel.stationSetting.isPollutionNotificationEnabled {
                Slider(value: $viewModel.stationSetting.pollutionTherhold, in: 1...500, step: 1)
            }

            if viewModel.stationSetting.pollutionTherhold < TOO_SMALL_POLLUTION {
                HStack {
                    Text("Settings.the_value_is_too_small_you_would_get_lots_of_notifications")
                        .font(.caption)
                        .fontWeight(.thin)

                    Spacer()
                }
            }

            // Cleanliness Notification
            Toggle(isOn: $viewModel.stationSetting.isCleanlinessNotificationEnabled) {
                Text("Settings.notice_me_when_aqi_is_below")
                    .fontWeight(.thin)

                LabelView(
                    airIndexTypes: AirIndexTypes.aqi,
                    value: viewModel.stationSetting.cleanlinessTherhold
                )
            }

            if viewModel.stationSetting.isCleanlinessNotificationEnabled {
                Slider(value: $viewModel.stationSetting.cleanlinessTherhold, in: 1...500, step: 1)
            }

            if viewModel.stationSetting.cleanlinessTherhold > TOO_LARGE_CLEANLINESS {
                HStack {
                    Text("Settings.the_value_is_too_large_you_would_get_lots_of_notifications")
                        .font(.caption)
                        .fontWeight(.thin)

                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }

    init(station: Station) {
        self.station = station
        self.viewModel = SettingsRowViewModel(station: station)
    }
}

//struct SettingsRow_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            SettingsRow(station: Station(name: "Yangming", nameLocal: "陽明", lat: 25.182722, lon: 121.529583))
//            SettingsRow(station: Station(name: "Songshan", nameLocal: "松山", lat: 25.050000, lon: 121.578611))
//        }
//        .previewLayout(.fixed(width: 400, height: 250))
//    }
//}
