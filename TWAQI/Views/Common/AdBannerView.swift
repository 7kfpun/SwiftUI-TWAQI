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
        VStack {
            Spacer()
            if !settings.isPro {
                GADBannerViewController(adUnitID: adUnitID)
                    .frame(width: kGADAdSizeBanner.size.width, height: kGADAdSizeBanner.size.height)
            }
        }
    }
}

struct AdBannerView_Previews: PreviewProvider {
    static var previews: some View {
        Separator().environmentObject(SettingsStore())
    }
}
