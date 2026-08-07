//
//  GADBannerView.swift
//  TWAQI
//
//  Created by kf on 17/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMobileAds
import SwiftUI
import UIKit

struct GADBannerViewController: UIViewControllerRepresentable {
    var adUnitID: String = "ca-app-pub-3940256099942544/2934735716"  // Testing id

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.frame = CGRect(origin: .zero, size: AdSizeBanner.size)

        let bannerView = BannerView(adSize: AdSizeBanner)
        bannerView.adUnitID = self.adUnitID
        bannerView.rootViewController = viewController
        bannerView.delegate = context.coordinator
        viewController.view.addSubview(bannerView)

        bannerView.load(Request())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    /// Without a delegate an ad that never arrives is completely silent — no log,
    /// no failure, just empty space. These logs make that diagnosable.
    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("AdMob: received ad for \(bannerView.adUnitID ?? "?")")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("AdMob: FAILED for \(bannerView.adUnitID ?? "?") — \(error.localizedDescription)")
        }
    }
}
