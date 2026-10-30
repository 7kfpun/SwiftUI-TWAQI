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

    /// Set when shown in the panel beside the map, which has no back button.
    private let onClose: (() -> Void)?

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
        Button(action: { ShareCardSharing.share(card: shareCard, stationId: viewModel.stationId) }) {
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
            locality: pollutant?.displayLocality,
            aqi: currentAqi,
            pollutant: pollutant,
            publishTime: viewModel.latestPublishTime
        )
    }

    private var favouriteButton: some View {
        Button(action: { self.viewModel.favouriteStationToggle() }) {
            Image(systemName: self.viewModel.isFavourited ? "heart.fill" : "heart")
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var page: some View {
        ScrollView {
            // Ordered as a reader's questions: what is it, where does that sit
            // on the scale, what is actually in the air, which way is that
            // heading, where is this station, what should I do, tell me next
            // time. The pollutant grid sits immediately above the chart it
            // drives, so tapping one visibly changes the other.
            VStack(alignment: .leading, spacing: 0) {
                header

                AqiScaleView(aqi: currentAqi)
                    .padding(.top, 4)
                    .padding(.bottom, 16)

                // What that number looks like outside.
                StationCamView(state: viewModel.cam)
                    .padding(.bottom, 16)

                Separator().frame(height: 8)

                if let pollutant = viewModel.pollutant {
                    PollutantGridView(pollutant: pollutant, selected: $selectedPollutant)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                }

                DetailsHistoryView(
                    historicalPollutants: viewModel.historicalPollutants,
                    airIndexType: selectedPollutant
                )

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
                if let pollutant = viewModel.pollutant {
                    let location = StationLocationView(pollutant: pollutant)
                    if location.hasContent {
                        location.padding(.vertical, 16)
                    }
                }
            }
            // A readable measure. Left unbounded, every row stretched the full
            // width of an iPad, which turned six pollutant cards into six
            // near-empty banners and the chart into a mural.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            // Clearance for the banner, reserved inside the scroll content.
            //
            // This screen is presented two ways: pushed inside the tab's
            // NavigationView, and modally from a map marker as a
            // UIHostingController wrapped in a UINavigationController. The
            // modal path did not apply the bottom `.safeAreaInset`, so the
            // banner sat on top of the last section instead of below it.
            // Reserving the space in the content works in both.
            .padding(.bottom, settings.isPro ? 0 : AdBannerView.height)
        }
        .overlay(alignment: .bottom) {
            AdBannerView(adUnitID: getEnv("AdUnitIdDetailsFooter")!)
        }
        .onAppear {
            self.getData()
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

    /// Live reading when available, else the newest history point.
    private var currentAqi: Double {
        viewModel.pollutant?.aqi ?? viewModel.historicalPollutants.last?.aqi ?? 0
    }

    private var stationTitle: String {
        viewModel.pollutant?.displayName
            ?? viewModel.station.map { Locale.isChinese ? $0.nameLocal : $0.name }
            ?? ""
    }

    private var header: some View {
        let pollutant = viewModel.pollutant

        return StationHeaderView(
            title: stationTitle,
            locality: pollutant?.displayLocality,
            area: pollutant?.displayArea,
            stationType: pollutant?.stationType ?? .unknown,
            aqi: pollutant?.aqi ?? viewModel.historicalPollutants.last?.aqi ?? 0,
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

struct DetailsView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsView(stationId: 91).environmentObject(SettingsStore())
    }
}
