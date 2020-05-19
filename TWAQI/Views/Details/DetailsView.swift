//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

//import SDWebImageSwiftUI
import SwiftUI

struct DetailsView: View {
    @ObservedObject var viewModel: DetailsViewModel

    var body: some View {
//        // SDImageCache.shared.config.maxDiskAge = 60 * 5  // This seems not working
//        let cacheKey = Date.currentTimeStamp / (1000 * 60 * 5)  // For caching images for 5 min
//
//        var imageUrl = ""
//
//        if let station = self.viewModel.station {
//            imageUrl = station.imageUrl ?? ""
//        }

        return ZStack {
            ScrollView {
                Spacer()
                    .frame(height: 80)
//                if !imageUrl.isEmpty {
//                    WebImage(url: URL(string: "\(imageUrl)?\(cacheKey)"))
//                        .resizable()
//                        .indicator(.activity)
//                        .transition(.fade)
//                        .aspectRatio(contentMode: .fill)
//                } else {
//                    Spacer()
//                        .frame(height: 80)
//                }

                if self.viewModel.station != nil {
                    SettingsRow(station: self.viewModel.station!)

                    Separator()
                }

                if !viewModel.historicalPollutants.isEmpty {
                    DetailsSuggestionView(lastPollutant: viewModel.historicalPollutants.last!)
                    Separator()
                }

                Indicator()

                DetailsHistoryView(historicalPollutants: viewModel.historicalPollutants)

                Separator()

                Spacer().frame(height: 50)
            }

            if !viewModel.isCustomAdLoading {
                if viewModel.isShowCustomAd {
                    CustomAdView(customAd: viewModel.customAd)
                        .onAppear(perform: submitImpressionEvent)
                } else {
                    AdBannerView(adUnitID: getEnv("AdUnitIdDetailsFooter")!)
                }
            }
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
        self.viewModel.getCustomAd()
        Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { (_) in
            // Schedule in seconds
            self.viewModel.getCustomAd()
        }
    }

    private func submitImpressionEvent() {
        if viewModel.isShowCustomAd {
            if let customAd = viewModel.customAd {
                var components = URLComponents(string: customAd.imageUrl)!
                components.query = nil

                TrackingManager.logEvent(eventName: "ad_custom_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])

                TrackingManager.logEvent(eventName: "ad_custom_\(customAd.name)_impression", parameters: [
                    "name": customAd.name,
                    "position": customAd.position,
                    "impressionRate": customAd.impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": customAd.destinationUrl,
                    "cpc": customAd.cpc,
                ])
            }
        }
    }
}

struct DetailsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsView(stationId: 1).environmentObject(SettingsStore())

            DetailsView(stationId: 2).environmentObject(SettingsStore())
        }
    }
}
