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
            SettingsRow(station: Station(name: "Yangming", nameLocal: "陽明", lon: 121.529583, lat: 25.182722))
            SettingsRow(station: Station(name: "Songshan", nameLocal: "松山", lon: 121.578611, lat: 25.050000))
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
