//
//  CustomAdView.swift
//  TWAQI
//
//  Created by kf on 20/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SDWebImageSwiftUI
import SwiftUI

struct CustomAdView: View {
    @EnvironmentObject var settings: SettingsStore

    var customAd: CustomAd?

    var body: some View {
        let imageUrl = customAd!.imageUrl
        return VStack {
            Spacer()
            if !settings.isPro && !imageUrl.isEmpty {
                Button(action: openUrl) {
                    WebImage(url: URL(string: imageUrl))
                        .resizable()
                        .transition(.fade)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 50)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func openUrl() {
        if let name = customAd?.name,
            let impressionRate = customAd?.impressionRate,
            let imageUrl = customAd?.imageUrl,
            let destinationUrl = customAd?.destinationUrl {
            print("destinationUrl", destinationUrl)
            if let url = URL(string: destinationUrl) {
                UIApplication.shared.open(url)

                var components = URLComponents(string: imageUrl)!
                components.query = nil

                TrackingManager.logEvent(eventName: "ad_custom_\(name)_click", parameters: [
                    "name": name,
                    "impressionRate": impressionRate,
                    "imageUrl": "\(components.url!)",
                    "destinationUrl": destinationUrl,
                ])
            }
        }
    }
}

struct CustomAdView_Previews: PreviewProvider {
    static var previews: some View {
        CustomAdView().environmentObject(SettingsStore())
    }
}
