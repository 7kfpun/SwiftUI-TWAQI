//
//  AdBannerView.swift
//  TWAQI
//
//  Created by kf on 5/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMobileAds
import SwiftUI

struct AdBannerView: View {
    @EnvironmentObject var settings: SettingsStore

    var adUnitID: String

    var body: some View {
        // Sized to the banner and nothing more. This is used as a
        // `.safeAreaInset(edge: .bottom)`, which measures the inset view's own
        // content — an enclosing `VStack { Spacer() ... }` reported maximal
        // height, so the inset claimed the whole screen and a full-screen
        // transparent view sat over the list swallowing every tap.
        if !settings.isPro {
            GADBannerViewController(adUnitID: adUnitID)
                .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
        }
    }
}

struct AdBannerView_Previews: PreviewProvider {
    static var previews: some View {
        Separator().environmentObject(SettingsStore())
    }
}
