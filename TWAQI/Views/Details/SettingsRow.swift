//
//  SettingsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsRow: View {
    // Owns its view model — see the note in DetailsView. Without this, toggling
    // a notification switch re-rendered the parent and reset the row's state.
    @StateObject private var viewModel: SettingsRowViewModel

    var station: Station

    let TOO_SMALL_POLLUTION = 110.0
    let TOO_LARGE_CLEANLINESS = 30.0

    var body: some View {
        // The station name used to head this block, repeating the page header a
        // scroll above it. The section is identified by what it does instead.
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "Details.notifications")

            threshold(
                title: "Settings.notice_me_when_aqi_is_above",
                isOn: $viewModel.setting.isAboveEnabled,
                value: $viewModel.setting.aboveThreshold,
                warning: viewModel.setting.aboveThreshold < TOO_SMALL_POLLUTION
                    ? "Settings.the_value_is_too_small_you_would_get_lots_of_notifications"
                    : nil
            )

            threshold(
                title: "Settings.notice_me_when_aqi_is_below",
                isOn: $viewModel.setting.isBelowEnabled,
                value: $viewModel.setting.belowThreshold,
                warning: viewModel.setting.belowThreshold > TOO_LARGE_CLEANLINESS
                    ? "Settings.the_value_is_too_large_you_would_get_lots_of_notifications"
                    : nil
            )

            switch viewModel.notice {
            case .denied:
                VStack(alignment: .leading, spacing: 8) {
                    caption("Settings.notifications_are_off")
                    Button("Settings.open_notification_settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            case .saveFailed:
                caption("Settings.alert_could_not_be_saved")
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.light)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One alert threshold: a switch, and — only once it's on — the value and
    /// the slider that sets it, side by side so the number reads as the
    /// slider's position rather than a stray chip.
    private func threshold(
        title: LocalizedStringKey,
        isOn: Binding<Bool>,
        value: Binding<Double>,
        warning: LocalizedStringKey?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Toggle("", isOn: isOn)
                    .labelsHidden()
            }

            if isOn.wrappedValue {
                HStack(spacing: 12) {
                    LabelView(airIndexTypes: AirIndexTypes.aqi, value: value.wrappedValue)

                    Slider(value: value, in: 1...500, step: 1)
                }

                // Nested inside the switch: this advice used to render even
                // when the alert was off, warning about a threshold that
                // wasn't in use.
                if let warning = warning {
                    Text(warning)
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    init(station: Station) {
        self.station = station
        _viewModel = StateObject(wrappedValue: SettingsRowViewModel(station: station))
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
