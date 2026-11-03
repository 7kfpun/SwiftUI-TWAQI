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
    @Published var showingPro = false

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
        }
        return true
    }
}
