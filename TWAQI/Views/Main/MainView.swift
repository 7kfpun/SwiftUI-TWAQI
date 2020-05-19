//
//  MainView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ZStack {
            GoogleMapController()
                .edgesIgnoringSafeArea(.all)

            if !viewModel.isCustomAdLoading {
                if viewModel.isShowCustomAd {
                    CustomAdView(customAd: viewModel.customAd)
                        .onAppear(perform: submitImpressionEvent)
                } else {
                    AdBannerView(adUnitID: getEnv("AdUnitIdMainFooter")!)
                }
            }
        }.onAppear(perform: getData)
    }

    private func getData() {
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

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(["iPhone SE", "iPhone XS Max"], id: \.self) { deviceName in
            MainView(viewModel: .init())
                .previewDevice(PreviewDevice(rawValue: deviceName))
                .previewDisplayName(deviceName)
        }
    }
}
