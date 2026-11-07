//
//  ConsentManager.swift
//  TWAQI
//
//  Created by kf on 8/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Combine
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// Google's User Messaging Platform (FOX-118): asks for ad consent where the
/// law requires it, before any ad is requested, and reopens the choice from
/// Help (EEA and UK). Mirrors Android's consent flow (FOX-58, FOX-116).
@MainActor
final class ConsentManager: ObservableObject {
    static let shared = ConsentManager()

    /// UMP says ads may be requested (consent given, or none needed here).
    @Published private(set) var canRequestAds: Bool
    /// Help shows its "Privacy settings" row only while this is true.
    @Published private(set) var privacyOptionsRequired: Bool

    private var didGather = false
    private var didStartAds = false

    private init() {
        let info = ConsentInformation.shared
        canRequestAds = info.canRequestAds
        privacyOptionsRequired = Self.showsPrivacyOptions(info.privacyOptionsRequirementStatus)
    }

    /// The visibility rule for the Help row: only when UMP says a privacy
    /// options entry point is required. Unknown (not yet fetched) and not
    /// required both hide it.
    nonisolated static func showsPrivacyOptions(_ status: PrivacyOptionsRequirementStatus) -> Bool {
        status == .required
    }

    /// Asks UMP for the current consent state and shows the form when one is
    /// needed, once per launch. Free users only: Pro has no ads, so nothing to
    /// ask. Starts the ads SDK only once UMP allows ad requests.
    func gather() {
        startAdsIfAllowed()
        guard !didGather else { return }
        didGather = true

        let parameters = RequestParameters()
        #if DEBUG
        // Launch argument `-UMPDebugGeographyEEA` forces the EEA flow.
        if ProcessInfo.processInfo.arguments.contains("-UMPDebugGeographyEEA") {
            let debug = DebugSettings()
            debug.geography = .EEA
            parameters.debugSettings = debug
        }
        #endif

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    print("UMP: consent info update failed — \(error.localizedDescription)")
                    self.refresh()
                    return
                }
                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController())
                } catch {
                    print("UMP: consent form failed — \(error.localizedDescription)")
                }
                self.refresh()
            }
        }
        // Consent stored by an earlier launch already allows ads.
        refresh()
    }

    /// Opens the privacy options form (Help → Privacy settings).
    func presentPrivacyOptions() {
        Task { @MainActor in
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController())
            } catch {
                print("UMP: privacy options form failed — \(error.localizedDescription)")
            }
            refresh()
        }
    }

    private func refresh() {
        let info = ConsentInformation.shared
        canRequestAds = info.canRequestAds
        privacyOptionsRequired = Self.showsPrivacyOptions(info.privacyOptionsRequirementStatus)
        startAdsIfAllowed()
    }

    private func startAdsIfAllowed() {
        guard canRequestAds, !didStartAds else { return }
        didStartAds = true
        MobileAds.shared.start(completionHandler: nil)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
