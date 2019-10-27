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
                } else {
                    Rectangle()
                        .fill(Color.white)
                        .frame(
                            width: 20,
                            height: 120
                        )
                        .cornerRadius(10, antialiased: true)
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
        Group {
            DetailsView(station: Station(
                name: "Matsu",
                nameLocal: "馬祖",
                lon: 119.949875,
                lat: 26.160469,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
            )).environmentObject(SettingsStore())

            DetailsView(station: Station(
                name: "Matsu",
                nameLocal: "馬祖",
                lon: 119.949875,
                lat: 26.160469
            )).environmentObject(SettingsStore())
        }
    }
}
