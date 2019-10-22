//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMobileAds
import SDWebImageSwiftUI
import SwiftUI

struct DetailsView: View {
    @ObservedObject var viewModel: DetailsViewModel

    var station: Station

    var body: some View {
        ZStack {
            ScrollView {
                if !(self.station.imageUrl?.isEmpty ?? true) {
                    WebImage(url: URL(string: self.station.imageUrl!))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                if !viewModel.historyPollutants.isEmpty {
                    DetailsSuggestionView(lastPollutant: viewModel.historyPollutants.last!)
                }

                Separator()

                SettingsRow(station: station)

                Separator()

                Indicator()
                    .frame(height: 90)

                DetailsHistoryView(historyPollutants: viewModel.historyPollutants)

                Separator()
            }

            VStack {
                Spacer()
                GADBannerViewController(adUnitID: getEnv("AdUnitIdHelpFooter")!)
                    .frame(width: kGADAdSizeBanner.size.width, height: kGADAdSizeBanner.size.height)
            }
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
        DetailsView(station: Station(
            name: "Matsu",
            nameLocal: "馬祖",
            lon: 119.949875,
            lat: 26.160469,
            imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
        )).environmentObject(SettingsStore())
    }
}
