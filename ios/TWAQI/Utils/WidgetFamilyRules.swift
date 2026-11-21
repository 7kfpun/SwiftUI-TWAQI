//
//  WidgetFamilyRules.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import WidgetKit

/// What each Home Screen / Lock Screen family of the phone widget does,
/// as a function of the family and Pro alone, so it can be tested without
/// a timeline context. Compiled into the app for its tests.
enum WidgetFamilyRules {
    /// Small, medium and large list favourites under the leading station.
    /// Extra large shows one station in detail instead (FOX-72); the Lock
    /// Screen families have no room.
    static func listsFavourites(_ family: WidgetFamily) -> Bool {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge: return true
        default: return false
        }
    }

    /// Medium, large and extra large are Pro sizes.
    static func isProFamily(_ family: WidgetFamily) -> Bool {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLarge: return true
        default: return false
        }
    }

    /// A Pro size placed without Pro. The gallery (`isPreview`) still shows
    /// it unlocked, so the reader sees what the size does.
    static func isLocked(_ family: WidgetFamily, isPro: Bool, isPreview: Bool) -> Bool {
        isProFamily(family) && !isPro && !isPreview
    }

    /// Small, medium and large show the weather at the station (FOX-181,
    /// TWAQ-17), and so does the rectangular Lock Screen widget (a line of
    /// temperature). Extra large, the circular and the inline Lock Screen
    /// widgets don't.
    static func showsWeather(_ family: WidgetFamily) -> Bool {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge: return true
        default:
            if #available(iOS 16.0, *) { return family == .accessoryRectangular }
            return false
        }
    }

    /// Extra large shows the station page (history, forecast, cam), and is
    /// the only family that fetches them.
    static func showsStationDetail(_ family: WidgetFamily) -> Bool {
        family == .systemExtraLarge
    }
}
