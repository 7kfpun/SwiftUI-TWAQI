//
//  DeepLink.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Where the Pro screen was opened from. Logged as `source` with every step
/// of the Pro funnel (`pro_screen_opened`, `pro_plan_selected`, the purchase
/// events); the widget's link carries it on `twaqi://pro` as `source`.
enum ProScreenSource: String {
    /// The "Ad-free" row in Help.
    case helpRow = "help_row"
    /// "See Pro plans" on the last step of the welcome flow.
    case onboarding
    /// The "Unlock with Pro" placeholder on a medium or large widget.
    case widgetLocked = "widget_locked"
    /// `twaqi://pro` with no `source`, or one this build doesn't know.
    case deepLink = "deep_link"
}

/// URLs the app opens on (`twaqi://`, declared in the app's Info.plist).
/// Shared with the widget, which builds the URL it opens the app with.
/// Only the Pro screen is routed; anything else is ignored.
enum DeepLink: Equatable {
    case pro(source: ProScreenSource)

    static let scheme = "twaqi"
    private static let proHost = "pro"
    private static let sourceItem = "source"

    /// `twaqi://pro?source=…`
    static func proURL(source: ProScreenSource) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = proHost
        components.queryItems = [URLQueryItem(name: sourceItem, value: source.rawValue)]
        return components.url
    }

    /// Nil for any URL that isn't one of ours.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == Self.proHost,
              components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
        else { return nil }

        let source = components.queryItems?
            .first { $0.name == Self.sourceItem }?
            .value
            .flatMap(ProScreenSource.init(rawValue:))
        self = .pro(source: source ?? .deepLink)
    }

    /// What the app should open for `url`, or nil to ignore it: unknown URLs,
    /// and the Pro screen for someone who already has Pro.
    static func route(_ url: URL, isPro: Bool) -> DeepLink? {
        guard let link = DeepLink(url: url) else { return nil }
        switch link {
        case .pro:
            return isPro ? nil : link
        }
    }
}
