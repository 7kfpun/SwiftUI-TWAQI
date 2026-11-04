//
//  AppRouter.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Combine
import Foundation

/// Screens the app was asked to open by URL. One per window scene;
/// `ContentView` presents from it so a link works whichever tab is showing.
final class AppRouter: ObservableObject {
    /// A station page opened by link: the Control Center control, or the
    /// "Open station" shortcut (FOX-74).
    struct OpenedStation: Identifiable, Equatable {
        let id: Int
    }

    @Published var showingPro = false

    @Published var openedStation: OpenedStation?

    /// Where the link that opened the Pro screen came from, handed to
    /// `ProView`, which logs it with each funnel step.
    private(set) var proSource: ProScreenSource = .deepLink

    /// Opens what `url` asks for. Returns false when it is ignored: not one
    /// of our URLs, or the Pro screen for someone who already has Pro.
    @discardableResult
    func open(_ url: URL, isPro: Bool) -> Bool {
        guard let link = DeepLink.route(url, isPro: isPro) else { return false }
        switch link {
        case .pro(let source):
            proSource = source
            showingPro = true
        case .station(let id, let source):
            TrackingManager.logEvent(.stationLinkOpened, parameters: [
                "source": source.rawValue,
                "stationId": id,
            ])
            openedStation = OpenedStation(id: id)
        }
        return true
    }
}
