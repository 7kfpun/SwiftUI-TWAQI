//
//  AirStatusTypes.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

enum AirStatuses: String, CaseIterable, Hashable {
    case good
    case moderate
    case unhealthyforsensitivegroup
    case unhealthy
    case veryunhealthy
    case hazardous
    case unknown

    static func getShowAllCases() -> [AirStatuses] {
        [
            AirStatuses.good,
            AirStatuses.moderate,
            AirStatuses.unhealthyforsensitivegroup,
            AirStatuses.unhealthy,
            AirStatuses.veryunhealthy,
            AirStatuses.hazardous,
        ]
    }

    func toString() -> LocalizedStringKey {
        let readableStrings = [
            "good": "AirStatus.good" as LocalizedStringKey,
            "moderate": "AirStatus.moderate" as LocalizedStringKey,
            "unhealthyforsensitivegroup": "AirStatus.unhealthyforsensitivegroup" as LocalizedStringKey,
            "unhealthy": "AirStatus.unhealthy" as LocalizedStringKey,
            "veryunhealthy": "AirStatus.veryunhealthy" as LocalizedStringKey,
            "hazardous": "AirStatus.hazardous" as LocalizedStringKey,
        ]
        return readableStrings[self.rawValue] ?? ""
    }

    /// 1 (good) … 6 (hazardous); 0 for `.unknown`. A second cue besides
    /// colour: the map marker draws this many pips (TWAQ-18).
    var level: Int {
        switch self {
        case .good: return 1
        case .moderate: return 2
        case .unhealthyforsensitivegroup: return 3
        case .unhealthy: return 4
        case .veryunhealthy: return 5
        case .hazardous: return 6
        case .unknown: return 0
        }
    }

    /// The band colour in the palette chosen under Help (TWAQ-18).
    func getColor() -> UInt32 {
        getColor(palette: .current)
    }

    func getColor(palette: AQIPalette) -> UInt32 {
        palette.color(for: self)
    }

    /// Text on the band colour: black or white, whichever is more legible
    /// (WCAG contrast ratio), so every band's text passes AA in every palette.
    func getForegroundColor() -> UInt32 {
        getForegroundColor(palette: .current)
    }

    func getForegroundColor(palette: AQIPalette) -> UInt32 {
        AQIContrast.legibleText(on: getColor(palette: palette))
    }

    func getImage() -> String {
        "status_\(self.rawValue)"
    }

    /// There is no `status_unknown` asset — a reading of 0 (or outside every
    /// band) has no face to show. Call sites must skip the image entirely
    /// rather than asking the catalog for one that doesn't exist.
    var hasFaceImage: Bool {
        self != .unknown
    }

    func getGeneralPublicGuidance() -> LocalizedStringKey {
        let readableStrings = [
            "good": "AirStatus.general_public_guidance_good" as LocalizedStringKey,
            "moderate": "AirStatus.general_public_guidance_moderate" as LocalizedStringKey,
            "unhealthyforsensitivegroup": "AirStatus.general_public_guidance_unhealthyforsensitivegroup" as LocalizedStringKey,
            "unhealthy": "AirStatus.general_public_guidance_unhealthy" as LocalizedStringKey,
            "veryunhealthy": "AirStatus.general_public_guidance_veryunhealthy" as LocalizedStringKey,
            "hazardous": "AirStatus.general_public_guidance_hazardous" as LocalizedStringKey,
        ]
        return readableStrings[self.rawValue] ?? ""
    }

    func getSensitivePublicGuidance() -> LocalizedStringKey {
        let readableStrings = [
            "good": "AirStatus.sensitive_group_guidance_good" as LocalizedStringKey,
            "moderate": "AirStatus.sensitive_group_guidance_moderate" as LocalizedStringKey,
            "unhealthyforsensitivegroup": "AirStatus.sensitive_group_guidance_unhealthyforsensitivegroup" as LocalizedStringKey,
            "unhealthy": "AirStatus.sensitive_group_guidance_unhealthy" as LocalizedStringKey,
            "veryunhealthy": "AirStatus.sensitive_group_guidance_veryunhealthy" as LocalizedStringKey,
            "hazardous": "AirStatus.sensitive_group_guidance_hazardous" as LocalizedStringKey,
        ]
        return readableStrings[self.rawValue] ?? ""
    }

    /// Colour bands for each index, lowest first: the thresholds every
    /// reading in the app is scored against. Ordered so the guide pages can
    /// list them; a dictionary had no order to show.
    static let bands: [AirIndexTypes: [(range: Range<Double>, status: AirStatuses)]] = [
        AirIndexTypes.aqi: [
            (1..<51, .good),
            (51..<101, .moderate),
            (101..<151, .unhealthyforsensitivegroup),
            (151..<201, .unhealthy),
            (201..<301, .veryunhealthy),
            (301..<100*10, .hazardous),
        ],
        AirIndexTypes.pm25: [
            (0.1..<15.5, .good),
            (15.5..<35.5, .moderate),
            (35.5..<54.5, .unhealthyforsensitivegroup),
            (54.5..<150.5, .unhealthy),
            (150.5..<250.5, .veryunhealthy),
            (250.5..<500.5*10, .hazardous),
        ],
        AirIndexTypes.pm10: [
            (1..<55, .good),
            (55..<126, .moderate),
            (126..<255, .unhealthyforsensitivegroup),
            (255..<355, .unhealthy),
            (355..<425, .veryunhealthy),
            (425..<605*10, .hazardous),
        ],
        AirIndexTypes.o3: [
            (1..<55, .good),
            (55..<125, .moderate),
            (125..<165, .unhealthyforsensitivegroup),
            (165..<205, .unhealthy),
            (205..<405, .veryunhealthy),
            (405..<605, .hazardous),
        ],
        AirIndexTypes.co: [
            (0.1..<4.5, .good),
            (4.5..<9.5, .moderate),
            (9.5..<12.5, .unhealthyforsensitivegroup),
            (12.5..<15.5, .unhealthy),
            (15.5..<30.5, .veryunhealthy),
            (30.5..<50.5, .hazardous),
        ],
        AirIndexTypes.so2: [
            (1..<36, .good),
            (36..<76, .moderate),
            (76..<186, .unhealthyforsensitivegroup),
            (186..<305, .unhealthy),
            (305..<605, .veryunhealthy),
            (605..<1005, .hazardous),
        ],
        AirIndexTypes.no2: [
            (1..<54, .good),
            (54..<101, .moderate),
            (101..<361, .unhealthyforsensitivegroup),
            (361..<650, .unhealthy),
            (650..<1250, .veryunhealthy),
            (1250..<2050, .hazardous),
        ],
    ]

    static func checkAirStatus(airIndexType: AirIndexTypes, value: Double) -> AirStatuses {
        bands[airIndexType]?.first { $0.range.contains(value) }?.status ?? .unknown
    }
}


/// The colours the AQI bands are drawn in (TWAQ-18). Which band a reading
/// falls in never changes; only the colour it is drawn with.
enum AQIPalette: String, CaseIterable, Identifiable {
    /// The official colours.
    case standard
    /// Blue → yellow → orange → vermilion → purple, picked from the Okabe–Ito
    /// set so the levels stay apart under red–green colour blindness.
    case colorBlindSafe

    static let defaultsKey = "aqiPalette"

    var id: String { rawValue }

    func color(for status: AirStatuses) -> UInt32 {
        switch self {
        case .standard:
            switch status {
            case .good: return 0x009866
            case .moderate: return 0xFEDE33
            case .unhealthyforsensitivegroup: return 0xFE9833
            case .unhealthy: return 0xCC0033
            case .veryunhealthy: return 0x660098
            case .hazardous: return 0x7E2200
            case .unknown: return 0x676767
            }
        case .colorBlindSafe:
            switch status {
            case .good: return 0x0072B2
            case .moderate: return 0xF0E442
            case .unhealthyforsensitivegroup: return 0xE69F00
            case .unhealthy: return 0xD55E00
            case .veryunhealthy: return 0xB5559A
            case .hazardous: return 0x7B61D6
            case .unknown: return 0x676767
            }
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AQIPalette {
        defaults.string(forKey: defaultsKey).flatMap(AQIPalette.init(rawValue:)) ?? .standard
    }

    /// The app reads its own defaults; the widget extension reads the mirror
    /// in the app group (`WidgetBridge` writes it), as for the language.
    static var current: AQIPalette {
        let isExtension = Bundle.main.bundlePath.hasSuffix(".appex")
        return stored(in: isExtension ? shared : .standard)
    }

    static var shared: UserDefaults {
        UserDefaults(suiteName: WatchStore.appGroup) ?? .standard
    }

    /// Writes `palette` into `shared`; `.standard` removes the key. Returns
    /// whether anything changed.
    @discardableResult
    static func mirror(_ palette: AQIPalette, to shared: UserDefaults) -> Bool {
        guard stored(in: shared) != palette else { return false }
        if palette == .standard {
            shared.removeObject(forKey: defaultsKey)
        } else {
            shared.set(palette.rawValue, forKey: defaultsKey)
        }
        return true
    }
}

/// WCAG 2.1 contrast maths for `0xRRGGBB` colours.
enum AQIContrast {
    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Black or white, whichever has the higher contrast on `background`.
    static func legibleText(on background: UInt32) -> UInt32 {
        ratio(0xFFFFFF, background) >= ratio(0x000000, background) ? 0xFFFFFF : 0x000000
    }
}
