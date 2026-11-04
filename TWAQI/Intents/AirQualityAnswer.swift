//
//  AirQualityAnswer.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// The station a Siri / Shortcuts question or the Control Center control is
/// answered for (FOX-74). Pure, so the choice can be tested apart from App
/// Intents and Core Location.
enum StationPlan: Equatable {
    /// A station by id: the one asked for, or the first favourite standing in
    /// for "nearest" when location isn't available.
    case station(Int)
    /// The station nearest the reader.
    case nearest
    /// The station nearest the 中正 default (`WatchAPI.defaultLocation`): no
    /// location and no favourite to fall back to.
    case defaultLocation
}

/// Said before the reading when "nearest" was asked for and something else
/// is answered.
enum StationFallbackNote: Equatable {
    case firstFavourite
    case defaultLocation
}

struct StationResolution: Equatable {
    let plan: StationPlan
    let note: StationFallbackNote?

    /// `requestedStationId` nil means "nearest". Location is used only when
    /// the app already has it (`locationAvailable`); it is never asked for
    /// here. Without it, the first favourite in the reader's order answers,
    /// and without one, the 中正 default.
    static func resolve(requestedStationId: Int?, favouriteIds: [Int], locationAvailable: Bool) -> StationResolution {
        if let requestedStationId {
            return StationResolution(plan: .station(requestedStationId), note: nil)
        }
        if locationAvailable {
            return StationResolution(plan: .nearest, note: nil)
        }
        if let first = favouriteIds.first {
            return StationResolution(plan: .station(first), note: .firstFavourite)
        }
        return StationResolution(plan: .defaultLocation, note: .defaultLocation)
    }
}

/// One entry in the station picker of the intents and the control: "Nearest"
/// first, then the favourites in the reader's order.
struct StationChoice: Equatable {
    static let nearestId = "nearest"

    let id: String
    let name: String

    var stationId: Int? { Int(id) }
    var isNearest: Bool { id == Self.nearestId }

    /// Favourites never fetched yet have no name in the cache; they are listed
    /// by id rather than left out, so the order still matches Favourites.
    static func choices(favouriteIds: [Int], readings: [WatchReading], locale: Locale, bundle: Bundle) -> [StationChoice] {
        let names = Dictionary(readings.map { ($0.stationId, $0) }, uniquingKeysWith: { _, latest in latest })
        var seen: Set<Int> = []
        let favourites = favouriteIds.compactMap { id -> StationChoice? in
            guard seen.insert(id).inserted else { return nil }
            return StationChoice(id: String(id), name: names[id].map { AirQualityAnswer.name(of: $0, locale: locale) } ?? "#\(id)")
        }
        return [nearest(bundle: bundle)] + favourites
    }

    static func nearest(bundle: Bundle) -> StationChoice {
        StationChoice(id: nearestId, name: bundle.localizedString(forKey: "Intent.station_nearest", value: nil, table: nil))
    }
}

/// What Siri says and Shortcuts shows for a reading, in the app's language.
enum AirQualityAnswer {
    /// Where the reading came from.
    enum Freshness: Equatable {
        /// Fetched just now.
        case live
        /// The last one saved in the app group, because the fetch failed.
        case cached
    }

    /// A live reading published longer ago than this says how old it is too:
    /// readings are hourly, so this is a station that has missed a publish.
    static let staleAfter: TimeInterval = 2 * 60 * 60

    static func text(
        reading: WatchReading?,
        freshness: Freshness,
        note: StationFallbackNote?,
        now: Date = Date(),
        locale: Locale,
        bundle: Bundle
    ) -> String {
        func localized(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: nil, table: nil)
        }

        var sentences: [String] = []
        switch note {
        case .firstFavourite: sentences.append(localized("Intent.answer_fallback_favourite"))
        case .defaultLocation: sentences.append(localized("Intent.answer_fallback_default"))
        case nil: break
        }

        guard let reading else {
            sentences.append(localized("Intent.answer_no_reading"))
            return join(sentences, locale: locale)
        }

        let status = reading.status(.aqi)
        let name = name(of: reading, locale: locale)
        guard status != .unknown else {
            sentences.append(String(format: localized("Intent.answer_no_aqi"), locale: locale, name))
            return join(sentences, locale: locale)
        }

        sentences.append(String(
            format: localized("Intent.answer_reading"), locale: locale,
            name, reading.formatted(.aqi), localized("AirStatus.\(status.rawValue)")
        ))
        if let pollutant = mainPollutant(of: reading) {
            sentences.append(String(format: localized("Intent.answer_main_pollutant"), locale: locale, pollutant.toString()))
        }
        sentences.append(String(
            format: localized("Intent.answer_guidance"), locale: locale,
            localized("AirStatus.general_public_guidance_\(status.rawValue)")
        ))

        if let age = age(of: reading, now: now) {
            let ageText = ageString(age, locale: locale)
            if freshness == .cached {
                sentences.append(String(format: localized("Intent.answer_cached_age"), locale: locale, ageText))
            } else if age > staleAfter {
                sentences.append(String(format: localized("Intent.answer_old_age"), locale: locale, ageText))
            }
        } else if freshness == .cached {
            sentences.append(localized("Intent.answer_cached"))
        }

        return join(sentences, locale: locale)
    }

    /// The pollutant in the worst band, named only when the AQI is past good,
    /// as MOENV names a 主要污染物 only above 50. Ties go to the first in
    /// PM2.5, PM10, O3, NO2, SO2, CO order. Nil when every pollutant is good.
    static func mainPollutant(of reading: WatchReading) -> AirIndexTypes? {
        let bands = AirStatuses.getShowAllCases()
        guard let aqiBand = bands.firstIndex(of: reading.status(.aqi)), aqiBand > 0 else { return nil }

        var main: (type: AirIndexTypes, band: Int)?
        for type in [AirIndexTypes.pm25, .pm10, .o3, .no2, .so2, .co] {
            guard let band = bands.firstIndex(of: reading.status(type)), band > (main?.band ?? 0) else { continue }
            main = (type, band)
        }
        return main?.type
    }

    /// The station's name in `locale`'s language, never blank.
    static func name(of reading: WatchReading, locale: Locale) -> String {
        let preferred = locale.isChinese ? reading.nameLocal : reading.name
        return preferred.isEmpty ? (reading.code.isEmpty ? "#\(reading.stationId)" : reading.code) : preferred
    }

    /// How long ago `reading` was published; nil when its time doesn't parse.
    static func age(of reading: WatchReading, now: Date) -> TimeInterval? {
        WatchStore.publishedDate(of: reading).map { max(0, now.timeIntervalSince($0)) }
    }

    /// "3 hours" / "3小時": the largest whole unit, at least a minute.
    static func ageString(_ age: TimeInterval, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = age >= 2 * 24 * 60 * 60 ? [.day] : (age >= 60 * 60 ? [.hour] : [.minute])
        return formatter.string(from: max(age, 60)) ?? ""
    }

    /// Chinese sentences run on; English ones take a space.
    private static func join(_ sentences: [String], locale: Locale) -> String {
        sentences.joined(separator: locale.isChinese ? "" : " ")
    }
}
