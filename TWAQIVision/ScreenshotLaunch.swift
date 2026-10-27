//
//  ScreenshotLaunch.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

#if DEBUG
import SwiftUI

/// Puts the app straight into a given state from launch arguments, for
/// screenshots: there is no way to pinch a pin or press an ornament button
/// from the command line. Debug builds only.
///
/// Read from the NSUserDefaults argument domain, like the iOS screenshot
/// tests' `-pro YES`:
///
///   -TWAQIStation 126            select a station on the map
///   -TWAQIIndex pm25             show another index
///   -TWAQIWindMode YES           wind arrows instead of pins
///   -TWAQINearest YES            find and select the nearest station
///   -TWAQIOpen browser|station   also open the station browser, or the
///                                selected station in its own window
///   -TWAQIBrowserTab favourites|search|help
///   -TWAQITabletop YES           open the immersive tabletop
enum ScreenshotLaunch {
    private static var defaults: UserDefaults { .standard }

    static var browserTab: String? { defaults.string(forKey: "TWAQIBrowserTab") }

    @MainActor
    static func apply(
        to store: StationStore,
        openWindow: OpenWindowAction,
        openImmersiveSpace: OpenImmersiveSpaceAction
    ) async {
        if let raw = defaults.string(forKey: "TWAQIIndex"), let index = AirIndexTypes(rawValue: raw) {
            store.index = index
        }
        if defaults.bool(forKey: "TWAQIWindMode") {
            store.isWindMode = true
        }

        // Arguments arrive as strings; `integer(forKey:)` parses them.
        let stationId = defaults.integer(forKey: "TWAQIStation") > 0 ? defaults.integer(forKey: "TWAQIStation") : nil
        store.selectedStationId = stationId
        if defaults.bool(forKey: "TWAQINearest") {
            // Waits for readings: the nearest is picked from them.
            while store.stations.isEmpty, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
            await store.selectNearest()
        }

        switch defaults.string(forKey: "TWAQIOpen") {
        case "browser":
            openWindow(single: BrowserView.id)
        case "station":
            if let id = stationId ?? store.selectedStationId {
                openWindow(id: StationWindow.id, value: id)
            }
        default:
            break
        }

        if defaults.bool(forKey: "TWAQITabletop") {
            _ = await openImmersiveSpace(id: TWAQIVisionApp.tabletopId)
        }
    }
}

/// Applies `ScreenshotLaunch` once per process, from the map volume.
struct ScreenshotLaunchModifier: ViewModifier {
    @Environment(StationStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @MainActor private static var hasApplied = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.hasApplied else { return }
            Self.hasApplied = true
            await ScreenshotLaunch.apply(to: store, openWindow: openWindow, openImmersiveSpace: openImmersiveSpace)
        }
    }
}
#endif
