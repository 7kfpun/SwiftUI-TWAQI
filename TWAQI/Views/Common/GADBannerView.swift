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

    func makeUIViewController(context: Context) -> UIViewController {
        let view = GADBannerView(adSize: kGADAdSizeBanner)
        let viewController = UIViewController()
        view.adUnitID = self.adUnitID
        view.rootViewController = viewController
        viewController.view.addSubview(view)
        viewController.view.frame = CGRect(origin: .zero, size: kGADAdSizeBanner.size)
        view.load(GADRequest())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
