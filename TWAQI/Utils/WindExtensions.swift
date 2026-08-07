//
//  WindExtensions.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import SwiftUI

/// Wind helpers shared by the map markers and the station detail screen.
///
/// `wind_direction` is meteorological — the direction the wind blows *from* —
/// in degrees clockwise from north.
struct Wind {
    let direction: Double
    let speed: Double

    /// The API reports `0 / 0` both for genuinely calm air and for stations with
    /// no anemometer. Either way there is no direction worth drawing.
    var isCalm: Bool {
        speed <= 0
    }

    private static let compassPoints = [
        "N", "NNE", "NE", "ENE",
        "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW",
        "W", "WNW", "NW", "NNW",
    ]

    /// 16-point compass abbreviation, e.g. `297°` → `WNW`.
    var compassPoint: String {
        guard !isCalm else { return "—" }
        let normalised = direction.truncatingRemainder(dividingBy: 360)
        let positive = normalised < 0 ? normalised + 360 : normalised
        let index = Int((positive / 22.5).rounded()) % 16
        return Wind.compassPoints[index]
    }

    /// Beaufort-flavoured descriptor for the speed alone.
    func toString() -> LocalizedStringKey {
        switch speed {
        case ..<0.3: return "Wind.calm"
        case ..<1.6: return "Wind.light_air"
        case ..<3.4: return "Wind.light_breeze"
        case ..<5.5: return "Wind.gentle_breeze"
        case ..<8.0: return "Wind.moderate_breeze"
        default: return "Wind.strong_breeze"
        }
    }

    /// Rotation for an arrow glyph that points the way the wind is *going*.
    var arrowRotation: Angle {
        .degrees(direction)
    }
}

extension Date {
    private static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // `publish_time` carries no timezone and is Taiwan local time.
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Parses the API's `publish_time`.
    static func fromApi(_ value: String) -> Date? {
        apiFormatter.date(from: value)
    }
}

extension String {
    /// `"2026-08-07T22:00:00"` → `"22:00"`, or the raw string if unparseable.
    var asPublishTime: String {
        guard let date = Date.fromApi(self) else { return self }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// `"2026-08-07T22:00:00"` → `"Aug 7, 22:00"` style, locale-aware.
    var asPublishDateTime: String {
        guard let date = Date.fromApi(self) else { return self }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Coarse "how stale is this reading" text, e.g. `"2h ago"`.
    var asRelativeAge: String {
        guard let date = Date.fromApi(self) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
