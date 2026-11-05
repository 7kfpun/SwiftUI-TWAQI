//
//  ComplicationStyle.swift
//  TWAQIWatchWidget
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// How a complication shows its index.
///
/// The `AppEnum` conformance lives with the widget, so this file needs no
/// AppIntents and the unit tests can compile it too.
enum ComplicationStyle: String, CaseIterable, Sendable {
    /// "AQI 42": the index name, the number and, with room, the unit.
    case labelled
    /// "42": just the number, for small slots and readers who know the index.
    case numberOnly
    /// The phone app's face for the band, with the number where it fits.
    /// Free without Pro, minus the number (FOX-63).
    case face
    /// "Moderate": the health level in words, no number at all.
    case status

    /// Every style but the face needs Pro; so does the face's number.
    var isPro: Bool { self != .face }
}

/// What a complication may draw for the reader (FOX-63).
enum ComplicationAccess: Equatable {
    /// Pro: the style as designed, number included.
    case full
    /// The free face: the band's face in its colour, never the number.
    case faceOnly
    /// A Pro style without Pro: a lock that reads "Pro", no reading.
    case locked

    init(style: ComplicationStyle, isPro: Bool) {
        if isPro {
            self = .full
        } else {
            self = style.isPro ? .locked : .faceOnly
        }
    }

    /// Whether the number (or the unit next to it) may be drawn.
    var showsNumber: Bool { self == .full }
}
