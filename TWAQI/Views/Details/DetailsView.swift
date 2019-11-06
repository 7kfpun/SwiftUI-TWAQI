//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SDWebImageSwiftUI
import SwiftUI

struct DetailsView: View {
    @ObservedObject var viewModel: DetailsViewModel

    var station: Station

    var body: some View {
        SDImageCache.shared.config.maxDiskAge = 60 * 2
        let imageUrl = self.station.imageUrl ?? ""

        return ZStack {
            ScrollView {
                if !imageUrl.isEmpty {
                    WebImage(url: URL(string: imageUrl))
                        .resizable()
                        .indicator(.activity)
                        .transition(.fade)
                        .frame(width: screenSize.width, height: screenSize.width * 720/1280)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Spacer()
                        .frame(width: screenSize.width, height: 80)
                }

                SettingsRow(station: station)

                Separator()

                if !viewModel.historyPollutants.isEmpty {
                    DetailsSuggestionView(lastPollutant: viewModel.historyPollutants.last!)
                    Separator()
                }

                Indicator()

                DetailsHistoryView(historyPollutants: viewModel.historyPollutants)

                Separator()
            }
            .padding(.bottom, 50)

            AdBanner(adUnitID: getEnv("AdUnitIdDetailsFooter")!)
        }
        .onAppear {
            self.getData()
        }
        .edgesIgnoringSafeArea(.top)
    }

    init(station: Station) {
        self.station = station
        self.viewModel = DetailsViewModel(station: station)
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct DetailsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsView(
                station: Station(
                    name: "Matsu",
                    nameLocal: "馬祖",
                    lon: 119.949875,
                    lat: 26.160469,
                    imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
                )
            ).environmentObject(SettingsStore())

            DetailsView(
                station: Station(
                    name: "Matsu",
                    nameLocal: "馬祖",
                    lon: 119.949875,
                    lat: 26.160469
                )
            ).environmentObject(SettingsStore())
        }
    }
}
