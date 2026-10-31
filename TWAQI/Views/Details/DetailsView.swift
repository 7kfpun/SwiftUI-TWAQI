//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsView: View {
    // `@StateObject`, not `@ObservedObject`: this view builds its own view model
    // in `init`, and SwiftUI re-runs `init` on every parent re-render. With
    // `@ObservedObject` each of those rebuilt an empty model and discarded the
    // fetched station, leaving the screen permanently blank because `onAppear`
    // had already fired. `@StateObject` constructs it once per view identity.
    @StateObject private var viewModel: DetailsViewModel

    /// Which pollutant the 24-hour chart is showing. Local to this screen on
    /// purpose — the old picker wrote to the global `airIndexTypeSelected`,
    /// which silently re-scored every marker on the map.
    @State private var selectedPollutant: AirIndexTypes = .aqi

    /// Needed to know whether the ad banner is taking space at the bottom.
    @EnvironmentObject var settings: SettingsStore

    /// Set when shown from the map, in the panel beside it or a sheet over
    /// it, neither of which has a back button.
    private let onClose: (() -> Void)?

    /// Bumped when an on-device translation of the township or address lands.
    @State private var translationRevision = 0

    /// Behind the share button. In a wide window (iPad, an unfolded iPhone
    /// Duo) the share sheet is a popover, and it should point at the button
    /// wherever the page sits: the panel beside the map, or the details
    /// column beside a list.
    @State private var shareAnchor = PopoverAnchor()

    var body: some View {
        // One `navigationBarItems` call per branch: a second call replaces the
        // first rather than adding to it.
        if let onClose = onClose {
            page.navigationBarItems(
                leading: Button(action: onClose) { Image(systemName: "xmark") },
                trailing: trailingButtons
            )
        } else {
            page.navigationBarItems(trailing: trailingButtons)
        }
    }

    private var trailingButtons: some View {
        HStack(spacing: 20) {
            shareButton
            favouriteButton
        }
    }

    /// Disabled until there is a reading: a card saying "—" is not worth
    /// sending anyone.
    private var shareButton: some View {
        Button(action: {
            ShareCardSharing.share(card: shareCard, stationId: viewModel.stationId, from: shareAnchor.view)
        }) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(PlainButtonStyle())
        .background(PopoverAnchorView(anchor: shareAnchor))
        .disabled(currentAqi <= 0)
        .accessibilityLabel(Text("Share.share"))
    }

    private var shareCard: ShareCardView {
        let pollutant = viewModel.pollutant

        return ShareCardView(
            title: stationTitle,
            locality: displayLocality,
            aqi: currentAqi,
            pollutant: pollutant,
            publishTime: viewModel.latestPublishTime
        )
    }

    private var favouriteButton: some View {
        // `settings` rather than the view model: the environment store
        // redraws when Favourites or an alert switch changes the list.
        let isFavourited = settings.savedFavouriteStations.contains(viewModel.stationId)

        return Button(action: { self.viewModel.favouriteStationToggle() }) {
            Image(systemName: isFavourited ? "heart.fill" : "heart")
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(isFavourited
            ? LocalizedStringKey("Favourites.remove_from_favourites")
            : LocalizedStringKey("Favourites.add_to_favourites")))
    }

    private var page: some View {
        ScrollView {
            // Ordered as a reader's questions: what is it, where does that sit
            // on the scale, what is actually in the air, which way is that
            // heading, where is this station, what should I do, tell me next
            // time. The pollutant grid sits immediately above the chart it
            // drives, so tapping one visibly changes the other.
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isShowingLastGood {
                    OfflineNotice()
                        .padding(.horizontal)
                        .padding(.top, 8)
                } else if viewModel.loadFailed {
                    OfflineEmptyStateView(retry: getData)
                        .padding(.bottom, 24)
                }

                header

                AqiScaleView(aqi: currentAqi)
                    .padding(.top, 4)
                    .padding(.bottom, 16)

                // Where that number is heading: the region's outlook. Absent,
                // not empty, when there is no forecast to show.
                if let forecast = viewModel.forecast {
                    AreaForecastView(forecast: forecast)
                        .padding(.bottom, 16)
                }

                // What that number looks like outside.
                StationCamView(state: viewModel.cam)
                    .padding(.bottom, 16)

                Separator().frame(height: 8)

                // Where the readings go: rather than a page of sections that
                // silently aren't there, or a saved reading passed off as live.
                if viewModel.isNotReporting {
                    NotReportingView()
                        .padding(.vertical, 16)
                }

                if let pollutant = viewModel.pollutant {
                    PollutantGridView(pollutant: pollutant, selected: $selectedPollutant)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                }

                // A retired station still returns its last 24 points, which
                // would read as today's trend.
                if !viewModel.isNotReporting || viewModel.hasRecentHistory {
                    DetailsHistoryView(
                        historicalPollutants: viewModel.historicalPollutants,
                        airIndexType: selectedPollutant
                    )
                }

                Separator().frame(height: 8)

                if let pollutant = viewModel.pollutant {
                    WindView(wind: pollutant.wind, tint: selectedTint(for: pollutant))
                        .padding(.vertical, 16)

                    Separator().frame(height: 8)
                }

                if currentAqi > 0 {
                    HealthGuidanceView(aqi: currentAqi)
                        .padding(.vertical, 16)

                    Separator().frame(height: 8)
                }

                if let station = viewModel.station {
                    SettingsRow(station: station)
                        .padding(.vertical, 16)

                    Separator().frame(height: 8)
                }

                // Fixed metadata last: it never changes, so it has no claim on
                // the space above the fold.
                if let location = location, location.hasContent {
                    location.padding(.vertical, 16)
                }
            }
            // A readable measure. Left unbounded, every row stretched the full
            // width of an iPad, which turned six pollutant cards into six
            // near-empty banners and the chart into a mural.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            // Clearance for the banner, reserved inside the scroll content.
            //
            // This screen is shown several ways: pushed or in the details
            // column from a list, and from a map marker in the panel beside
            // the map or a sheet over it. The modal path once did not apply
            // the bottom `.safeAreaInset`, so the banner sat on top of the
            // last section instead of below it. Reserving the space in the
            // content works in all of them.
            .padding(.bottom, settings.isPro ? 0 : AdBannerView.height)
        }
        .overlay(alignment: .bottom) {
            AdBannerView(adUnitID: getEnv("AdUnitIdDetailsFooter")!)
        }
        .onAppear {
            self.getData()
        }
        .translatesOnDevice(translatableLocation, revision: $translationRevision)
        // On the page, not the heart: an alert on a navigation-bar item's
        // content may not present on iOS 15.
        .alert(
            Text("Favourites.remove_station_with_alerts_title"),
            isPresented: $viewModel.isConfirmingUnfavourite
        ) {
            Button(role: .destructive, action: viewModel.removeFromFavourites) {
                Text("Favourites.remove_and_turn_off_alerts")
            }
            Button(role: .cancel, action: {}) {
                Text("Favourites.cancel")
            }
        } message: {
            Text("Favourites.remove_station_with_alerts_message")
        }
        // Favourited, but its alerts couldn't be switched on: one line on
        // why, and the way to fix it when it's a setting.
        .alert(
            Text("Favourites.added_to_favourites"),
            isPresented: isShowingFavouriteAlertsHint,
            presenting: viewModel.favouriteAlertsHint
        ) { hint in
            if hint == .notificationsDenied {
                Button(action: openNotificationSettings) {
                    Text("Favourites.open_settings")
                }
            }
            Button(role: .cancel, action: {}) {
                Text("Favourites.ok")
            }
        } message: { hint in
            switch hint {
            case .capReached:
                Text("Favourites.alerts_cap_reached_message")
            case .notificationsDenied:
                Text("Favourites.notifications_off_message")
            }
        }
    }

    private var isShowingFavouriteAlertsHint: Binding<Bool> {
        Binding(
            get: { viewModel.favouriteAlertsHint != nil },
            set: { if !$0 { viewModel.favouriteAlertsHint = nil } }
        )
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Band colour of the pollutant the page is currently showing, so the wind
    /// arrow matches the highlighted reading and the chart above it.
    private func selectedTint(for pollutant: Pollutant) -> Color {
        let status = AirStatuses.checkAirStatus(
            airIndexType: selectedPollutant,
            value: pollutant.getValue(airIndexType: selectedPollutant)
        )
        return Color(status.getColor())
    }

    /// Live (or saved, at most a week old and timestamped) reading when
    /// available, else the newest history point — unless the station has
    /// stopped reporting, when that point may be years old and must not be
    /// shown, scored or shared as the air now.
    private var currentAqi: Double {
        if let pollutant = viewModel.pollutant { return pollutant.aqi }
        if viewModel.isNotReporting, !viewModel.hasRecentHistory { return 0 }
        return viewModel.historicalPollutants.last?.aqi ?? 0
    }

    /// From the live reading, else the station record — fixed metadata, so a
    /// station with no reading still says where it is.
    /// The street address is translated on device outside Chinese.
    private var location: StationLocationView? {
        // Read so a finished translation redraws.
        _ = translationRevision
        var location: StationLocationView
        if let pollutant = viewModel.pollutant {
            location = StationLocationView(pollutant: pollutant)
        } else if let station = viewModel.station {
            location = StationLocationView(station: station)
        } else {
            return nil
        }
        let address = location.address
        location.displayAddress = address.map(OnDeviceTranslation.display)
        return location
    }

    private var stationTitle: String {
        viewModel.pollutant?.displayName
            ?? viewModel.station.map { Locale.isChinese ? $0.nameLocal : $0.name }
            ?? ""
    }

    /// Township and street address come from the API in Chinese only; outside
    /// Chinese they are translated on device when the language is installed.
    /// From the live reading, else the station record, like `location`.
    private var translatableLocation: [String] {
        if let pollutant = viewModel.pollutant {
            return [pollutant.township, pollutant.address].compactMap { $0 }
        }
        guard let station = viewModel.station else { return [] }
        return [station.township, station.address].compactMap { $0 }
    }

    /// "Banqiao District, New Taipei City": the township translated on device.
    private var displayLocality: String? {
        // Read so a finished translation redraws.
        _ = translationRevision
        return viewModel.pollutant?.displayLocality(township: OnDeviceTranslation.display)
            ?? viewModel.station?.displayLocality(township: OnDeviceTranslation.display)
    }

    private var header: some View {
        let pollutant = viewModel.pollutant
        let station = viewModel.station

        return StationHeaderView(
            title: stationTitle,
            locality: displayLocality,
            area: pollutant?.displayArea ?? station?.displayArea,
            stationType: pollutant?.stationType ?? station?.stationType ?? .unknown,
            aqi: currentAqi,
            publishTime: viewModel.latestPublishTime
        )
    }

    init(stationId: Int, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(stationId: stationId))
        self.onClose = onClose
    }

    private func getData() {
        self.viewModel.getData()
    }
}

extension StationLocationView {
    /// For a station with no current reading: the station record carries the
    /// same address and position. Here rather than beside `init(pollutant:)`
    /// because visionOS shares that file but not the `Station` model.
    init(station: Station) {
        self.init(
            address: station.address,
            coordinateText: String(format: "%.6f, %.6f", station.lat, station.lon)
        )
    }
}

/// The station is listed but has no current reading: retired, or offline for
/// maintenance. Says so, instead of leaving the readings sections blank.
private struct NotReportingView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(.secondary)

            Text("Details.not_reporting")
                .font(.headline)
                .fontWeight(.regular)

            Text("Details.not_reporting_message")
                .font(.callout)
                .fontWeight(.light)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
    }
}

struct DetailsView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsView(stationId: 91).environmentObject(SettingsStore())
    }
}
