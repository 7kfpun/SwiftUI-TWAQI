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

    /// The share button opens a preview of the card first (FOX-73).
    @State private var showingSharePreview = false

    /// Behind the "Send feedback" link at the foot of the page.
    @State private var showingFeedback = false

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
        Button(action: { showingSharePreview = true }) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(PlainButtonStyle())
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
        // Not until the station is known to exist (FOX-74).
        .disabled(!isFavourited && !viewModel.canAddFavourite)
        .accessibilityLabel(Text(isFavourited
            ? LocalizedStringKey("Favourites.remove_from_favourites")
            : LocalizedStringKey("Favourites.add_to_favourites")))
    }

    private var page: some View {
        ScrollView {
            // Ordered as a reader's questions (FOX-25): what is the air now,
            // tell me when it changes, what should I do, where is it heading
            // and what does it look like, what exactly is in it, then where
            // this station is.
            //
            // Alerts sit straight under the reading: from a map marker this
            // page opens as a half-height sheet, and on a small phone the
            // first screen ends about there, so anything lower is only found
            // by those who already scroll. The pollutant grid sits
            // immediately above the chart it drives, so tapping one visibly
            // changes the other, and wind follows them because its arrow
            // takes the selected pollutant's colour.
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

                // Tell me next time: the reason to come back, promoted from
                // near the bottom of the page.
                if let station = viewModel.station {
                    SettingsRow(station: station)
                        .padding(.bottom, 16)
                } else if viewModel.stationLoadFailed {
                    // Offline, or the station record failed: the card says
                    // so rather than silently not being there.
                    AlertsUnavailableCard(retry: getData)
                        .padding(.bottom, 16)
                }

                // What to do about the number above: two short lines, so it
                // costs little space this high up.
                if currentAqi > 0 {
                    HealthGuidanceView(aqi: currentAqi)
                        .padding(.bottom, 16)
                }

                Separator().frame(height: 8)

                // Where that number is heading, the weather behind it, and
                // what it looks like outside. The forecast and the weather
                // are absent, not empty, when there is none to show.
                VStack(alignment: .leading, spacing: 16) {
                    if let forecast = viewModel.forecast {
                        AreaForecastView(forecast: forecast)
                    }

                    if let weather = viewModel.weather {
                        StationWeatherView(weather: weather, countyTitle: viewModel.weatherCountyTitle)
                    }

                    StationCamView(state: viewModel.cam)
                }
                .padding(.vertical, 16)

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

                // Fixed metadata last: it never changes, so it has no claim on
                // the space above the fold.
                if let location = location, location.hasContent {
                    location.padding(.vertical, 16)
                }

                // Low-key and last, so it never pushes the alerts card down.
                feedbackLink
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
            AdBannerView(adUnitID: getEnv("AdUnitIdDetailsFooter")!, placement: .details)
        }
        .onAppear {
            self.getData()
        }
        // A sheet rather than a push: this page is also shown in the panel
        // beside the map and in a sheet over it, which have no stack to push
        // onto. Its own stack, so the form keeps its title bar on iPad too.
        .sheet(isPresented: $showingFeedback) {
            NavigationView {
                FeedbackView(source: .stationPage)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Feedback.cancel") { showingFeedback = false }
                        }
                    }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .environment(\.locale, settings.appLanguage.locale())
        }
        // On the page, not the button: a sheet on a navigation-bar item's
        // content may not present on iOS 15. The system share sheet then
        // opens from the preview, its popover on the preview's Share button.
        .sheet(isPresented: $showingSharePreview) {
            ShareCardPreviewView(card: shareCard, stationId: viewModel.stationId)
                .environment(\.locale, settings.appLanguage.locale())
        }
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
                Text("Favourites.alerts_cap_reached_message \(FavouriteAlerts.maxAlertedStations)")
            case .notificationsDenied:
                Text("Favourites.notifications_off_message")
            }
        }
    }

    private var feedbackLink: some View {
        Button(action: { showingFeedback = true }) {
            Label("Details.send_feedback", systemImage: "bubble.left")
                .font(.footnote)
        }
        .buttonStyle(BorderlessButtonStyle())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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
    /// The street address shows as the API writes it, in Chinese: machine
    /// translation garbles Taiwan street names (FOX-117).
    private var location: StationLocationView? {
        var location: StationLocationView
        if let pollutant = viewModel.pollutant {
            location = StationLocationView(pollutant: pollutant)
        } else if let station = viewModel.station {
            location = StationLocationView(station: station)
        } else {
            return nil
        }
        location.displayAddress = location.address
        return location
    }

    private var stationTitle: String {
        viewModel.pollutant?.displayName
            ?? viewModel.station.map { Locale.isChinese ? $0.nameLocal : $0.name }
            ?? ""
    }

    /// "Banqiao District, New Taipei City": outside Chinese the township comes
    /// from the fixed table of official names, never machine translation.
    private var displayLocality: String? {
        viewModel.pollutant?.displayLocality(township: TaiwanPlaceNames.displayTownship)
            ?? viewModel.station?.displayLocality(township: TaiwanPlaceNames.displayTownship)
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
            coordinateText: String(format: "%.6f, %.6f", station.lat, station.lon),
            lat: station.lat,
            lon: station.lon,
            stationName: station.displayName,
            aqi: nil
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
