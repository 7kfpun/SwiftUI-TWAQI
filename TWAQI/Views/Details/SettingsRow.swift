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
            .disabled(viewModel.isDisabled && !viewModel.stationSetting.isPollutionNotificationEnabled)

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
            .disabled(viewModel.isDisabled && !viewModel.stationSetting.isCleanlinessNotificationEnabled)

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

            if viewModel.isDisabled {
                Text("Settings.you_can_only_enable_at_most_for_two_stations")
                    .font(.caption)
                    .fontWeight(.thin)
            }
        }
        .padding(.horizontal)
    }

    init(station: Station) {
        self.station = station
        self.viewModel = SettingsRowViewModel(station: station)
    }
}

struct SettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsRow(station: Station(
                id: 0,
                countryId: 1,
                countryCode: "twn",
                code: "Yangming",
                lat: 25.182722,
                lon: 121.529583,
                imageUrl: "",
                name: "Yangming",
                nameLocal: "陽明"
            ))
            SettingsRow(station: Station(
                id: 1,
                countryId: 1,
                countryCode: "twn",
                code: "Songshan",
                lat: 25.050000,
                lon: 121.578611,
                imageUrl: "",
                name: "Songshan",
                nameLocal: "松山"
            ))
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
