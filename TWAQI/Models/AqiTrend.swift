//
//  AqiTrend.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

enum AqiTrendDirection {
    case improving
    case worsening
    case steady
}

/// Which way air quality is heading over the recent past.
///
/// Lives outside the view so it can be tested: the answer to "is this getting
/// better or worse" is the one piece of judgement on the station screen, and it
/// is easy to get subtly wrong.
struct AqiTrend: Equatable {
    var direction: AqiTrendDirection
    /// Absolute change between the two comparison windows, in whatever unit the
    /// values were given — AQI points, µg/m³, ppm.
    var magnitude: Double
    /// Mean of the most recent window — what the reader is experiencing now.
    var current: Double

    /// Absolute change rounded to whole AQI points. Only meaningful for AQI;
    /// pollutants measured in ppm round to zero, so those read `magnitude`.
    var change: Int { Int(magnitude.rounded()) }

    /// Movement smaller than this is noise, not a trend. Sized for AQI points;
    /// other pollutants pass their own via `from(values:steadyThreshold:)`.
    static let steadyThreshold = 5.0

    /// A pollutant-agnostic threshold: a tenth of the average reading. CO moves
    /// in hundredths of a ppm and PM10 in tens of µg/m³, so a single absolute
    /// cut-off would call one of them steady forever and the other volatile.
    static func relativeThreshold(for values: [Double]) -> Double {
        let average = mean(values)
        guard average > 0 else { return .greatestFiniteMagnitude }
        return average * 0.10
    }

    private static let windowSize = 3
    private static let lookBack = 6

    /// Compares the mean of the three most recent readings against the mean of
    /// the three from roughly six hours earlier.
    ///
    /// Averaging both ends matters: comparing a single latest reading against a
    /// single older one flips direction on any one-hour spike, and hourly AQI is
    /// spiky. Returns `nil` when there is too little history to say anything.
    ///
    /// - Parameters:
    ///   - values: readings, **oldest first**.
    ///   - steadyThreshold: movement below this counts as no change. Defaults to
    ///     the AQI-point threshold.
    static func from(
        values: [Double],
        steadyThreshold: Double = AqiTrend.steadyThreshold
    ) -> AqiTrend? {
        guard values.count >= 2 else { return nil }

        let recent = mean(Array(values.suffix(windowSize)))
        let earlier = mean(earlierWindow(in: values))
        let delta = recent - earlier

        let direction: AqiTrendDirection
        if abs(delta) < steadyThreshold {
            direction = .steady
        } else if delta < 0 {
            direction = .improving
        } else {
            direction = .worsening
        }

        return AqiTrend(
            direction: direction,
            magnitude: abs(delta),
            current: recent
        )
    }

    /// The three readings ending `lookBack` hours before the newest one, or the
    /// oldest three when there isn't that much history.
    private static func earlierWindow(in values: [Double]) -> [Double] {
        let needed = windowSize + lookBack
        guard values.count >= needed else {
            return Array(values.prefix(windowSize))
        }
        let upper = values.count - lookBack
        return Array(values[(upper - windowSize)..<upper])
    }

    private static func mean(_ slice: [Double]) -> Double {
        slice.isEmpty ? 0 : slice.reduce(0, +) / Double(slice.count)
    }
}
