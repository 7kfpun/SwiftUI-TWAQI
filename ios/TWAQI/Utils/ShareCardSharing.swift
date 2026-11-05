//
//  ShareCardSharing.swift
//  TWAQI
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import LinkPresentation
import Photos
import SwiftUI
import UIKit

/// What the reader did with the card, for `.shareCard`'s `action`.
enum ShareCardAction: String {
    /// Opened the system share sheet with the card.
    case share
    /// Saved the card to Photos.
    case save
    /// Closed the preview without sharing or saving.
    case cancel
}

/// Turns a `ShareCardView` into an image and hands it to the system share
/// sheet or Photos. The preview sheet (`ShareCardPreviewView`) comes first.
@MainActor
enum ShareCardSharing {
    nonisolated static let appStoreURL = URL(string: "https://apps.apple.com/app/id1286516443")!

    /// The line sent with the card: "Keelung: AQI 54, Moderate — via Taiwan Air".
    /// `bundle` is the app's language; tests pass an `.lproj`.
    static func message(title: String, aqi: Double, bundle: Bundle = .appLanguage) -> String {
        let status = AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi)
        return String(
            format: NSLocalizedString("Share.message", bundle: bundle, comment: ""),
            title,
            Int(aqi),
            NSLocalizedString("AirStatus.\(status.rawValue)", bundle: bundle, comment: "")
        )
    }

    /// The message and the App Store link, as the share sheet's text.
    static func shareText(title: String, aqi: Double, bundle: Bundle = .appLanguage) -> String {
        "\(message(title: title, aqi: aqi, bundle: bundle))\n\(appStoreURL.absoluteString)"
    }

    /// `sourceView` sits behind the share button, for the popover's arrow in
    /// a wide window. Without one it points at the top-right corner.
    static func share(image: UIImage, card: ShareCardView, from sourceView: UIView? = nil) {
        let message = message(title: card.title, aqi: card.aqi)
        present(
            items: [CardItemSource(image: image, title: message), shareText(title: card.title, aqi: card.aqi)],
            sourceView: sourceView
        )
    }

    enum SaveResult: Equatable {
        case saved
        /// The reader has said no to adding photos; only Settings can undo it.
        case denied
        case failed
    }

    /// Asks only for add-only access, which can't read the library.
    static func saveToPhotos(_ image: UIImage) async -> SaveResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .saved
        } catch {
            return .failed
        }
    }

    /// The preview opened: the top of the share funnel.
    static func logPreviewOpened(card: ShareCardView, stationId: Int) {
        TrackingManager.logEvent(.shareCardPreviewOpened, parameters: parameters(card: card, stationId: stationId))
    }

    static func log(_ action: ShareCardAction, card: ShareCardView, stationId: Int) {
        TrackingManager.logEvent(.shareCard, parameters: parameters(card: card, stationId: stationId, action: action))
    }

    /// The analytics parameters; `action` only on `.shareCard`.
    static func parameters(card: ShareCardView, stationId: Int, action: ShareCardAction? = nil) -> [String: Any] {
        var parameters: [String: Any] = [
            "stationId": stationId,
            "aqi": Int(card.aqi),
            "shape": card.shape.rawValue,
        ]
        parameters["action"] = action?.rawValue
        return parameters
    }

    /// At the card's shape, 1080 px wide.
    static func render(_ card: ShareCardView) -> UIImage? {
        let size = card.shape.size
        // Rendered outside the SwiftUI tree, so the Help language is passed in.
        let card = card.environment(\.locale, .app)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: card)
            renderer.scale = ShareCardShape.renderScale
            return renderer.uiImage
        }

        // iOS 15 has no ImageRenderer. A hosting controller that is never put
        // in a window has no safe area, so the card lays out at exactly its
        // frame.
        let controller = UIHostingController(rootView: card)
        let bounds = CGRect(origin: .zero, size: size)
        controller.view.bounds = bounds
        controller.view.backgroundColor = .clear
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = ShareCardShape.renderScale
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    /// Presented from UIKit, over whatever is on top: the preview sheet, which
    /// may itself be over the station sheet on the map.
    private static func present(items: [Any], sourceView: UIView?) {
        guard let presenter = topViewController() else { return }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Only in a wide window: a narrow one shows the sheet from the bottom.
        if let popover = activity.popoverPresentationController {
            if let sourceView = sourceView, sourceView.window != nil {
                // On an unfolded iPhone Duo or an iPad the preview is a form
                // sheet; the arrow points at its Share button.
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
                popover.permittedArrowDirections = [.up, .down]
            } else {
                // No button to point at: the top-right corner.
                let view = presenter.view!
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.maxX - 60, y: view.safeAreaInsets.top, width: 1, height: 1)
                popover.permittedArrowDirections = .up
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

/// One opening of the share preview (FOX-73), for its `cancel` event: the
/// sheet closed with no share and no successful save.
///
/// A share or a successful save commits the session for good; a failed or
/// denied save never undoes that. A save still running when the sheet goes
/// leaves the call to that save: it logs `cancel` only if it fails. A class,
/// so a save that ends after the sheet is gone still reaches it.
@MainActor
final class ShareCardSession {
    private(set) var isCommitted = false
    private var savesInFlight = 0
    private var isGone = false
    private var didCancel = false

    func appeared() {
        isGone = false
    }

    func shared() {
        isCommitted = true
    }

    func saveStarted() {
        savesInFlight += 1
    }

    /// Whether to log `cancel` now.
    func saveFinished(saved: Bool) -> Bool {
        savesInFlight = max(0, savesInFlight - 1)
        if saved { isCommitted = true }
        return cancelIfDue()
    }

    /// Whether to log `cancel` now.
    func disappeared() -> Bool {
        isGone = true
        return cancelIfDue()
    }

    private func cancelIfDue() -> Bool {
        guard isGone, !isCommitted, savesInFlight == 0, !didCancel else { return false }
        didCancel = true
        return true
    }
}

/// Holds the UIKit view behind a SwiftUI button, for a popover to point at.
/// Its frame can't be read reliably from SwiftUI: navigation bar items are
/// hosted apart from the page, so `.global` there isn't the window's space.
final class PopoverAnchor {
    weak var view: UIView?
}

struct PopoverAnchorView: UIViewRepresentable {
    let anchor: PopoverAnchor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        anchor.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        anchor.view = uiView
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
