//
//  ShareCardSharing.swift
//  TWAQI
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI
import UIKit

/// Turns a `ShareCardView` into an image and hands it to the system share
/// sheet.
@MainActor
enum ShareCardSharing {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id1286516443")!

    /// 3x the card's point size: 1080 × 1350, the 4:5 size feeds and stories
    /// take without cropping.
    private static let scale: CGFloat = 3

    static func share(card: ShareCardView, stationId: Int) {
        guard let image = render(card) else { return }

        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: card.aqi)
        let message = String(
            format: NSLocalizedString("Share.message", comment: ""),
            card.title,
            Int(card.aqi),
            "AirStatus.\(status.rawValue)".localized
        )

        present(items: [image, "\(message)\n\(appStoreURL.absoluteString)"])

        TrackingManager.logEvent(eventName: "share_card", parameters: [
            "stationId": stationId,
            "aqi": Int(card.aqi),
        ])
    }

    static func render(_ card: ShareCardView) -> UIImage? {
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: card)
            renderer.scale = scale
            return renderer.uiImage
        }

        // iOS 15 has no ImageRenderer. A hosting controller that is never put
        // in a window has no safe area, so the card lays out at exactly its
        // frame.
        let controller = UIHostingController(rootView: card)
        let bounds = CGRect(origin: .zero, size: ShareCardView.size)
        controller.view.bounds = bounds
        controller.view.backgroundColor = .clear
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    /// Presented from UIKit rather than a SwiftUI sheet: the station screen is
    /// also shown modally from a map marker inside a UIKit navigation
    /// controller, and a share sheet inside a sheet looks wrong on iPad.
    private static func present(items: [Any]) {
        guard let presenter = topViewController() else { return }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            // The share button sits in the top-right of the navigation bar.
            let view = presenter.view!
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.maxX - 60, y: view.safeAreaInsets.top, width: 1, height: 1)
            popover.permittedArrowDirections = .up
        }
        presenter.present(activity, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
