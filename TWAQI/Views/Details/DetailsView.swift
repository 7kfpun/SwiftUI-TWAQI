//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsView: View {
    @ObservedObject var viewModel: DetailsViewModel

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    Separator().frame(height: 8)

                    if let pollutant = viewModel.pollutant {
                        StationInfoView(pollutant: pollutant)
                            .padding(.vertical, 16)

                        Separator().frame(height: 8)
                    }

                    if let lastPollutant = viewModel.historicalPollutants.last {
                        DetailsSuggestionView(lastPollutant: lastPollutant)

                        Separator().frame(height: 8)
                    }

                    Indicator()
                        .padding(.top, 8)

                    DetailsHistoryView(historicalPollutants: viewModel.historicalPollutants)

                    Separator().frame(height: 8)

                    if let station = viewModel.station {
                        SettingsRow(station: station)
                            .padding(.vertical, 12)
                    }

                    Spacer().frame(height: 60)
                }
            }

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
        self.viewModel = DetailsViewModel(stationId: stationId)
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
