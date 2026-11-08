//
//  AdBannerView.swift
//  TWAQI
//
//  Created by kf on 5/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMobileAds
import SwiftUI

/// Which screen a banner sits on, logged with `ad_banner_tapped`.
enum AdPlacement: String {
    case main
    case details
    case detailsList = "details_list"
    case favourites
    case help
}

struct AdBannerView: View {
    @EnvironmentObject var settings: SettingsStore
    /// No ad is requested until UMP allows it (FOX-118).
    @ObservedObject private var consent = ConsentManager.shared

    var adUnitID: String
    var placement: AdPlacement

    /// The space the banner occupies. Scroll views that pin the banner over
    /// their own bounds — rather than handing it to `.safeAreaInset` — reserve
    /// this much at the end of their content so the last row can clear it.
    static let height = AdSizeBanner.size.height

    var body: some View {
        // Sized to the banner and nothing more. This is used as a
        // `.safeAreaInset(edge: .bottom)`, which measures the inset view's own
        // content — an enclosing `VStack { Spacer() ... }` reported maximal
        // height, so the inset claimed the whole screen and a full-screen
        // transparent view sat over the list swallowing every tap.
        if !settings.isPro && consent.canRequestAds {
            GADBannerViewController(adUnitID: adUnitID, placement: placement)
                .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
        }
    }
}

extension View {
    /// Puts the banner in its own strip under this view. Unlike
    /// `.safeAreaInset`, the list never scrolls beneath the banner, so the
    /// banner covers no row (FOX-180).
    func adBannerBelow(adUnitID: String, placement: AdPlacement) -> some View {
        VStack(spacing: 0) {
            self
            AdBannerView(adUnitID: adUnitID, placement: placement)
        }
    }
}

struct AdBannerView_Previews: PreviewProvider {
    static var previews: some View {
        Separator().environmentObject(SettingsStore())
    }
}
