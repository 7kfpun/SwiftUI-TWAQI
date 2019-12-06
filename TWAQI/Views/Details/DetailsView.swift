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

    var body: some View {
        // SDImageCache.shared.config.maxDiskAge = 60 * 5  // This seems not working
        let cacheKey = Date.currentTimeStamp / (1000 * 60 * 5)  // For caching images for 5 min

        var imageUrl = ""

        if let station = self.viewModel.station {
            imageUrl = station.imageUrl ?? ""
        }

        return ZStack {
            ScrollView {
                if !imageUrl.isEmpty {
                    WebImage(url: URL(string: "\(imageUrl)?\(cacheKey)"))
                        .resizable()
                        .indicator(.activity)
                        .transition(.fade)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Spacer()
                        .frame(height: 80)
                }

                if self.viewModel.station != nil {
                    SettingsRow(station: self.viewModel.station!)

                    Separator()
                }

                if !viewModel.historyPollutants.isEmpty {
                    DetailsSuggestionView(lastPollutant: viewModel.historyPollutants.last!)
                    Separator()
                }

                Indicator()

                DetailsHistoryView(historyPollutants: viewModel.historyPollutants)

                Separator()

                Spacer().frame(height: 50)
            }

            AdBannerView(adUnitID: getEnv("AdUnitIdDetailsFooter")!)
        }
        .onAppear {
            self.getData()
        }
        .edgesIgnoringSafeArea(.top)
        .navigationBarItems(trailing: Button(action: { self.viewModel.favouriteStationToggle() }) {
            Image(systemName: self.viewModel.isFavourited ? "heart.fill" : "heart")
        }
        .buttonStyle(PlainButtonStyle()))
    }

    init(stationId: Int) {
        self.viewModel = DetailsViewModel(stationId: stationId)
    }

    private func getData() {
        self.viewModel.getData()
    }
}

//struct DetailsView_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            DetailsView(
//                station: Station(
//                    name: "Matsu",
//                    nameLocal: "馬祖",
//                    lat: 26.160469,
//                    lon: 119.949875,
//                    imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
//                )
//            ).environmentObject(SettingsStore())
//
//            DetailsView(
//                station: Station(
//                    name: "Matsu",
//                    nameLocal: "馬祖",
//                    lat: 26.160469,
//                    lon: 119.949875
//                )
//            ).environmentObject(SettingsStore())
//        }
//    }
//}
