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
    private var didDebugReset = false
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

    /// The consent form and the ads SDK are for free users only, decided from
    /// the live Pro state (`SettingsStore.refreshPro()` has answered), never
    /// from a cached flag a caller saw earlier.
    nonisolated static func shouldPresentForm(livePro: Bool) -> Bool { !livePro }

    nonisolated static func shouldStartAds(livePro: Bool, canRequestAds: Bool, didStart: Bool) -> Bool {
        !livePro && canRequestAds && !didStart
    }

    private var livePro: Bool { UserDefaults.standard.bool(forKey: "pro") }

    /// Asks UMP for the current consent state, so Help knows whether to offer
    /// the privacy options entry point. That runs for Pro too (a Pro user may
    /// have chosen while free and can still withdraw). Only free users get the
    /// form and the ads SDK: Pro has no ads to ask about. Pro is refreshed
    /// first, so a stale cached flag (fresh install, restore, another device,
    /// a lapse) decides nothing.
    func gather() {
        #if DEBUG
        // Launch argument `-UMPReset` forgets the stored choice, so the form
        // can be checked again on the same install. Before anything starts ads.
        if !didDebugReset, ProcessInfo.processInfo.arguments.contains("-UMPReset") {
            didDebugReset = true
            ConsentInformation.shared.reset()
        }
        #endif
        // Claim the request before the first await: ContentView calls gather()
        // from onAppear and again on scenePhase .active, and both would
        // otherwise pass the guard while refreshPro() is suspended.
        let shouldRequest = !didGather
        didGather = true
        Task { @MainActor in
            await SettingsStore.refreshPro()
            startAdsIfAllowed()
            guard shouldRequest else { return }
            requestConsentInfo()
        }
    }

    private func requestConsentInfo() {
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
                // Right before the form: the answer may have changed since gather.
                await SettingsStore.refreshPro()
                guard Self.shouldPresentForm(livePro: self.livePro) else {
                    // Pro: no form. Ask again on a later trigger, in case Pro lapses this launch.
                    self.didGather = false
                    self.refresh()
                    return
                }
                // The welcome cover may still be dismissing; presenting over it fails.
                let top = await Self.settledTopViewController()
                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: top)
                } catch {
                    print("UMP: consent form failed — \(error.localizedDescription)")
                    // Not shown: ask again on the next trigger rather than skip until a cold start.
                    self.didGather = false
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
            await SettingsStore.refreshPro()
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
        // Free users only, whichever path got here. Callers refresh Pro first.
        guard Self.shouldStartAds(livePro: livePro, canRequestAds: canRequestAds, didStart: didStartAds) else { return }
        didStartAds = true
        MobileAds.shared.start(completionHandler: nil)
    }

    /// The top view controller once nothing is mid-dismissal (up to 2 s).
    private static func settledTopViewController() async -> UIViewController? {
        for _ in 0..<10 {
            if let top = topViewController(), !top.isBeingDismissed, !top.isBeingPresented {
                return top
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return topViewController()
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
