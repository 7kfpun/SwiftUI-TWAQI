//
//  ShareCardSharing.swift
//  TWAQI
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import LinkPresentation
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

    /// `sourceFrame` is the share button's frame in the window, for the
    /// popover's arrow in a wide window. Empty falls back to the top-right
    /// corner, where the button usually is.
    static func share(card: ShareCardView, stationId: Int, from sourceFrame: CGRect = .zero) {
        guard let image = render(card) else { return }

        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: card.aqi)
        let message = String(
            format: "Share.message".localized,
            card.title,
            Int(card.aqi),
            "AirStatus.\(status.rawValue)".localized
        )

        present(
            items: [CardItemSource(image: image, title: message), "\(message)\n\(appStoreURL.absoluteString)"],
            sourceFrame: sourceFrame
        )

        TrackingManager.logEvent(eventName: "share_card", parameters: [
            "stationId": stationId,
            "aqi": Int(card.aqi),
        ])
    }

    static func render(_ card: ShareCardView) -> UIImage? {
        // Rendered outside the SwiftUI tree, so the Help language is passed in.
        let card = card.environment(\.locale, .app)
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
    /// also shown in a sheet over the map, and a share sheet inside a sheet
    /// looks wrong on iPad.
    private static func present(items: [Any], sourceFrame: CGRect) {
        guard let presenter = topViewController() else { return }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Only in a wide window: a narrow one shows the sheet from the bottom.
        if let popover = activity.popoverPresentationController {
            let view = presenter.view!
            popover.sourceView = view
            if sourceFrame.isEmpty {
                // The share button sits in the top-right of the navigation bar.
                popover.sourceRect = CGRect(x: view.bounds.maxX - 60, y: view.safeAreaInsets.top, width: 1, height: 1)
                popover.permittedArrowDirections = .up
            } else {
                // From the window's coordinates. On an unfolded iPhone Duo or
                // an iPad the page may be the right-hand pane, the left-hand
                // one, or the whole window.
                popover.sourceRect = view.convert(sourceFrame, from: nil)
                popover.permittedArrowDirections = [.up, .down]
            }
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

/// The card as a share-sheet item. Handing over a bare `UIImage` alongside the
/// text let the sheet pick the text for its header, which showed a generic
/// text icon; this supplies the card itself as the preview.
private final class CardItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        metadata.iconProvider = NSItemProvider(object: image)
        return metadata
    }
}
