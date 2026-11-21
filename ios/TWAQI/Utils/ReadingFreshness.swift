//
//  ReadingFreshness.swift
//  TWAQI
//
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Whether a reading may be shown as current (TWAQ-19).
///
/// MOENV publishes hourly, so a reading a little over an hour old is still the
/// newest there is. Past `staleAfter` it is not: the station has stopped
/// reporting or the feed is late, and the screen must say so rather than show
/// the number as if it were fresh. A reading read back from the offline cache
/// after a failed request is `.offline` however recent its publish time.
enum ReadingFreshness: Equatable {
    /// Newer than `staleAfter`, from a request that succeeded.
    case fresh
    /// From a request that succeeded, but published longer ago than `staleAfter`
    /// (or at a time that can't be read).
    case stale
    /// The saved copy shown because the latest request failed.
    case offline

    /// An hour of publishing plus half an hour of lag.
    static let staleAfter: TimeInterval = 90 * 60

    static func decide(publishTime: String?, isFromCache: Bool, now: Date = Date()) -> ReadingFreshness {
        if isFromCache { return .offline }
        guard let age = age(of: publishTime, now: now) else { return .stale }
        // Exactly `staleAfter` is still fresh. A publish time slightly in the
        // future (clock skew) has a negative age and is fresh too.
        return age > staleAfter ? .stale : .fresh
    }

    /// Seconds since `publishTime`, which the API expresses in `Asia/Taipei`.
    /// Nil when it is missing or not a timestamp.
    static func age(of publishTime: String?, now: Date = Date()) -> TimeInterval? {
        guard let publishTime, let date = Date.fromApi(publishTime) else { return nil }
        return now.timeIntervalSince(date)
    }

    /// "12 min ago", in the app's language; empty when `publishTime` can't be read.
    static func ageText(of publishTime: String?, now: Date = Date()) -> String {
        guard let publishTime, let date = Date.fromApi(publishTime) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .app
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Lets pull-to-refresh wait for a screen's request to answer: `refreshable`
/// keeps its spinner up until the async closure returns. Main thread only,
/// like the view models that own one.
final class RefreshGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    /// The request answered, whether it succeeded or failed.
    func finish() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}
