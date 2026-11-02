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

    private static let tooSmallPollution = 110.0
    private static let tooLargeCleanliness = 30.0

    var body: some View {
        // A card near the top of the page rather than a labelled block at the
        // bottom (FOX-25): it heads itself with what it does and whether it is
        // on, so it reads as an invitation when off and a status when on. The
        // station name used to head this block, repeating the page header; it
        // is still left out.
        AlertsCard(isOn: viewModel.alertsState == .ready ? isOn : nil) {
            threshold(
                title: "Settings.notice_me_when_aqi_is_above",
                isOn: $viewModel.stationSetting.isPollutionNotificationEnabled,
                value: $viewModel.stationSetting.pollutionTherhold,
                warning: viewModel.stationSetting.pollutionTherhold < Self.tooSmallPollution
                    ? "Settings.the_value_is_too_small_you_would_get_lots_of_notifications"
                    : nil
            )

            threshold(
                title: "Settings.notice_me_when_aqi_is_below",
                isOn: $viewModel.stationSetting.isCleanlinessNotificationEnabled,
                value: $viewModel.stationSetting.cleanlinessTherhold,
                warning: viewModel.stationSetting.cleanlinessTherhold > Self.tooLargeCleanliness
                    ? "Settings.the_value_is_too_large_you_would_get_lots_of_notifications"
                    : nil
            )

            status
        }
    }

    /// One line under the switches on why they can't be used, if they can't.
    @ViewBuilder
    private var status: some View {
        switch viewModel.alertsState {
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                AlertsCaption("Details.alerts_checking")
            }
        case .unavailable:
            AlertsUnavailableNotice(retry: viewModel.reload)
        case .ready:
            if viewModel.saveFailed {
                AlertsCaption("Details.alerts_save_failed")
            }
            if viewModel.isAtCap {
                AlertsCaption("Settings.you_can_only_enable_at_most_for_two_stations")
            }
        }
    }

    /// Whether either switch below is on. Read from the row's own setting, so
    /// it follows the switches, and a clear from Favourites, with no plumbing
    /// of its own.
    private var isOn: Bool {
        viewModel.stationSetting.isPollutionNotificationEnabled
            || viewModel.stationSetting.isCleanlinessNotificationEnabled
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
        // Locked until OneSignal has been read. After that, only other
        // stations being at the two-station limit locks a switch that is
        // off; one that is on must stay switchable off.
        let locked = viewModel.alertsState != .ready || (viewModel.isAtCap && !isOn.wrappedValue)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(locked ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .disabled(locked)
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
                    AlertsCaption(warning)
                }
            }
        }
    }

    init(station: Station) {
        self.station = station
        _viewModel = StateObject(wrappedValue: SettingsRowViewModel(station: station))
    }
}

/// The alerts card's frame: the bell, what alerts do and — when known —
/// whether they are on, above `content`.
struct AlertsCard<Content: View>: View {
    /// Nil while it isn't known: no badge rather than a wrong "Off".
    var isOn: Bool?
    @ViewBuilder var content: Content

    private static var cornerRadius: CGFloat { 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(12)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .padding(.horizontal)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isOn == true ? "bell.badge.fill" : "bell")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Details.alerts_title")
                    .font(.headline)

                Text("Details.alerts_pitch")
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let isOn = isOn {
                Text(isOn ? "Details.alerts_on" : "Details.alerts_off")
                    .font(.caption.weight(.medium))
                    .foregroundColor(isOn ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isOn ? Color.accentColor : Color(.tertiarySystemFill))
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The alerts card when its station hasn't loaded, so there is nothing to
/// switch yet: says why, rather than leaving the card out (FOX-37 M6).
struct AlertsUnavailableCard: View {
    var retry: () -> Void

    var body: some View {
        AlertsCard(isOn: nil) {
            AlertsUnavailableNotice(retry: retry)
        }
    }
}

/// Alerts can't be read or changed right now, and a way to try again.
struct AlertsUnavailableNotice: View {
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                AlertsCaption("Details.alerts_unavailable")
            } icon: {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: retry) {
                Text("Details.alerts_try_again")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct AlertsCaption: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.light)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
        .previewLayout(.sizeThatFits)
    }
}
