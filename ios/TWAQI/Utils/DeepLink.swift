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

/// What opened a station's page by link (FOX-74). Logged as `source` with
/// `station_link_opened`.
enum StationLinkSource: String {
    /// The Control Center / Lock Screen / Action button control.
    case control
    /// The "Open station" App Shortcut.
    case shortcut
    /// A tap on a medium or large Home Screen widget, on the station it
    /// shows (FOX-76).
    case widget
    /// A tap on a push alert, on the station it is about (FOX-141).
    case push
    /// A Home Screen quick action: a favourite, or "Closest station" once it
    /// resolved to a station (FOX-138).
    case quickAction = "quick_action"
    /// `twaqi://station` with no `source`, or one this build doesn't know.
    case deepLink = "deep_link"
}

/// URLs the app opens on (`twaqi://`, declared in the app's Info.plist).
/// Shared with the widget, which builds the URL it opens the app with.
/// The Pro screen and a station's page are routed; anything else is ignored.
enum DeepLink: Equatable {
    case pro(source: ProScreenSource)
    case station(id: Int, source: StationLinkSource)

    static let scheme = "twaqi"
    private static let proHost = "pro"
    private static let stationHost = "station"
    private static let sourceItem = "source"
    private static let idItem = "id"

    /// `twaqi://pro?source=…`
    static func proURL(source: ProScreenSource) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = proHost
        components.queryItems = [URLQueryItem(name: sourceItem, value: source.rawValue)]
        return components.url
    }

    /// `twaqi://station?id=…&source=…`
    static func stationURL(stationId: Int, source: StationLinkSource) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = stationHost
        components.queryItems = [
            URLQueryItem(name: idItem, value: String(stationId)),
            URLQueryItem(name: sourceItem, value: source.rawValue),
        ]
        return components.url
    }

    /// The station link for a tapped push alert's payload (FOX-141): the
    /// sender puts `station_id` in the data as a string (FCM data is strings
    /// only). Nil when it is missing or not a positive whole number, so the
    /// tap just opens the app.
    static func pushTapURL(userInfo: [AnyHashable: Any]) -> URL? {
        let id: Int?
        switch userInfo["station_id"] {
        case let string as String: id = Int(string.trimmingCharacters(in: .whitespaces))
        case let number as NSNumber: id = number.intValue
        default: id = nil
        }
        guard let id, id > 0 else { return nil }
        return stationURL(stationId: id, source: .push)
    }

    /// Nil for any URL that isn't one of ours.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
        else { return nil }

        func item(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }

        switch components.host?.lowercased() {
        case Self.proHost:
            self = .pro(source: item(Self.sourceItem).flatMap(ProScreenSource.init(rawValue:)) ?? .deepLink)
        case Self.stationHost:
            guard let id = item(Self.idItem).flatMap(Int.init), id > 0 else { return nil }
            self = .station(id: id, source: item(Self.sourceItem).flatMap(StationLinkSource.init(rawValue:)) ?? .deepLink)
        default:
            return nil
        }
    }

    var isPro: Bool {
        if case .pro = self { return true }
        return false
    }

    /// What the app should open for `url`, or nil to ignore it: unknown URLs,
    /// the Pro screen for someone who already has Pro, and a station the app
    /// doesn't know. The custom scheme can be opened by any web page or app,
    /// so `twaqi://station?id=999999` must not open a page for a station that
    /// isn't there (FOX-74).
    static func route(_ url: URL, isPro: Bool, isKnownStation: (Int) -> Bool) -> DeepLink? {
        guard let link = DeepLink(url: url) else { return nil }
        switch link {
        case .pro:
            return isPro ? nil : link
        case .station(let id, _):
            return isKnownStation(id) ? link : nil
        }
    }
}

/// The Home Screen quick actions on the app icon (FOX-138): "Closest
/// station", then up to `maxFavourites` favourites in Favourites' order. Each
/// opens its station through the same `twaqi://station` path as a widget tap.
/// This is only the pure part; `SceneDelegate` sets them on `UIApplication`.
enum QuickActions {
    /// iOS shows four quick actions; one is "Closest station".
    static let maxFavourites = 3

    /// Posted when the favourites, their names or the language changed and
    /// the icon's quick actions should be rebuilt. The widget extension
    /// shares `WidgetBridge`, so the posting side cannot touch UIKit.
    static let didChange = Notification.Name("TWAQI.QuickActions.didChange")

    private static let typePrefix = "twaqi.quickaction."
    static let closestType = typePrefix + "closest"
    private static let stationTypePrefix = typePrefix + "station."

    struct Item: Equatable {
        let type: String
        let title: String
    }

    enum Target: Equatable {
        case closest
        case station(Int)
    }

    /// "Closest station" first, then the favourites. `favourites` is already
    /// in the reader's order; duplicates and non-positive ids are skipped.
    static func items(favourites: [(id: Int, name: String)], closestTitle: String) -> [Item] {
        var seen: Set<Int> = []
        let stations = favourites
            .filter { $0.id > 0 && seen.insert($0.id).inserted }
            .prefix(maxFavourites)
            .map { Item(type: stationTypePrefix + String($0.id), title: $0.name) }
        return [Item(type: closestType, title: closestTitle)] + stations
    }

    /// What a tapped quick action asks for; nil for a type that isn't ours.
    static func target(forType type: String) -> Target? {
        if type == closestType { return .closest }
        guard type.hasPrefix(stationTypePrefix),
              let id = Int(type.dropFirst(stationTypePrefix.count)), id > 0
        else { return nil }
        return .station(id)
    }
}
