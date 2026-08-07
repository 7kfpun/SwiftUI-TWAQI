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

    var body: some View {
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
                    StationInfoView(pollutant: pollutant)
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
                        .padding(.vertical, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AdBannerView(adUnitID: getEnv("AdUnitIdDetailsFooter")!)
        }
        .onAppear {
            self.getData()
        }
        .navigationBarItems(trailing: Button(action: { self.viewModel.favouriteStationToggle() }) {
            Image(systemName: self.viewModel.isFavourited ? "heart.fill" : "heart")
        }
        .buttonStyle(PlainButtonStyle()))
    }

    /// Live reading when available, else the newest history point.
    private var currentAqi: Double {
        viewModel.pollutant?.aqi ?? viewModel.historicalPollutants.last?.aqi ?? 0
    }

    private var header: some View {
        let pollutant = viewModel.pollutant

        return StationHeaderView(
            title: pollutant?.displayName
                ?? viewModel.station.map { Locale.isChinese ? $0.nameLocal : $0.name }
                ?? "",
            locality: pollutant?.displayLocality,
            area: pollutant?.displayArea,
            stationType: pollutant?.stationType ?? .unknown,
            aqi: pollutant?.aqi ?? viewModel.historicalPollutants.last?.aqi ?? 0,
            publishTime: viewModel.latestPublishTime
        )
    }

    init(stationId: Int) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(stationId: stationId))
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
