//
//  Constants.swift
//  TWAQI
//
//  Created by kf on 19/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

enum Constants {
    enum AirIndexTypes: String, CaseIterable, Hashable {
        case aqi
        case pm25
        case pm10
        case o3
        case co
        case so2
        case no2

        func toString() -> String {
            let readableStrings = [
                "aqi": "AQI",
                "pm25": "PM2.5",
                "pm10": "PM10",
                "o3": "O3",
                "co": "CO",
                "so2": "SO2",
                "no2": "NO2",
            ]
            return readableStrings[self.rawValue] ?? ""
        }

        func getMeaning() -> LocalizedStringKey {
            let units = [
                "aqi": "AirIndex.meaning_aqi" as LocalizedStringKey,
                "pm25": "AirIndex.meaning_pm25" as LocalizedStringKey,
                "pm10": "AirIndex.meaning_pm10" as LocalizedStringKey,
                "o3": "AirIndex.meaning_o3" as LocalizedStringKey,
                "co": "AirIndex.meaning_co" as LocalizedStringKey,
                "so2": "AirIndex.meaning_so2" as LocalizedStringKey,
                "no2": "AirIndex.meaning_no2" as LocalizedStringKey,
            ]
            return units[self.rawValue] ?? ""
        }

        func getDescription() -> LocalizedStringKey {
            let units = [
                "aqi": "AirIndex.description_aqi" as LocalizedStringKey,
                "pm25": "AirIndex.description_pm25" as LocalizedStringKey,
                "pm10": "AirIndex.description_pm10" as LocalizedStringKey,
                "o3": "AirIndex.description_o3" as LocalizedStringKey,
                "co": "AirIndex.description_co" as LocalizedStringKey,
                "so2": "AirIndex.description_so2" as LocalizedStringKey,
                "no2": "AirIndex.description_no2" as LocalizedStringKey,
            ]
            return units[self.rawValue] ?? ""
        }

        func getUnit() -> String {
            let units = [
                "aqi": "",
                "pm25": "μg/m3",
                "pm10": "μg/m3",
                "o3": "ppb",
                "co": "ppm",
                "so2": "ppb",
                "no2": "ppb",
            ]
            return units[self.rawValue] ?? ""
        }
    }

    enum AirStatuses: String, CaseIterable, Hashable {
        case good
        case moderate
        case unhealthyforsensitivegroup
        case unhealthy
        case veryunhealthy
        case hazardous
        case unknown

        static func getShowAllCases() -> [Constants.AirStatuses] {
            [
                Constants.AirStatuses.good,
                Constants.AirStatuses.moderate,
                Constants.AirStatuses.unhealthyforsensitivegroup,
                Constants.AirStatuses.unhealthy,
                Constants.AirStatuses.veryunhealthy,
                Constants.AirStatuses.hazardous,
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

        func getColor() -> UInt32 {
            let colors = [
                "good": 0x009866,
                "moderate": 0xFEDE33,
                "unhealthyforsensitivegroup": 0xFE9833,
                "unhealthy": 0xCC0033,
                "veryunhealthy": 0x660098,
                "hazardous": 0x7E2200,
            ]
            return UInt32(colors[self.rawValue] ?? 0xEEEEEE)
        }

        func getForegroundColor() -> UInt32 {
            let white = 0xFFFFFF
            let black = 0x000000
            let colors = [
                "good": white,
                "moderate": black,
                "unhealthyforsensitivegroup": black,
                "unhealthy": white,
                "veryunhealthy": white,
                "hazardous": white,
            ]
            return UInt32(colors[self.rawValue] ?? white)
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

        static func checkAirStatus(airIndexType: Constants.AirIndexTypes, value: Double) -> Constants.AirStatuses {
            let rangeMaps: [Constants.AirIndexTypes: [Range<Double>: Constants.AirStatuses]] = [
                Constants.AirIndexTypes.aqi: [
                    1..<51: .good,
                    51..<101: .moderate,
                    101..<151: .unhealthyforsensitivegroup,
                    151..<201: .unhealthy,
                    201..<301: .veryunhealthy,
                    301..<501: .hazardous,
                ],
                Constants.AirIndexTypes.pm25: [
                    0.0..<15.5: .good,
                    15.5..<35.5: .moderate,
                    35.5..<54.5: .unhealthyforsensitivegroup,
                    54.5..<150.5: .unhealthy,
                    150.5..<250.5: .veryunhealthy,
                    250.5..<500.5: .hazardous,
                ],
                Constants.AirIndexTypes.pm10: [
                    0..<55: .good,
                    55..<126: .moderate,
                    126..<255: .unhealthyforsensitivegroup,
                    255..<355: .unhealthy,
                    355..<425: .veryunhealthy,
                    425..<605: .hazardous,
                ],
                Constants.AirIndexTypes.o3: [
                    0..<55: .good,
                    55..<125: .moderate,
                    125..<165: .unhealthyforsensitivegroup,
                    165..<205: .unhealthy,
                    205..<405: .veryunhealthy,
                    405..<605: .hazardous,
                ],
                Constants.AirIndexTypes.co: [
                    0.0..<4.5: .good,
                    4.5..<9.5: .moderate,
                    9.5..<12.5: .unhealthyforsensitivegroup,
                    12.5..<15.5: .unhealthy,
                    15.5..<30.5: .veryunhealthy,
                    30.5..<50.5: .hazardous,
                ],
                Constants.AirIndexTypes.so2: [
                    0..<36: .good,
                    36..<76: .moderate,
                    76..<186: .unhealthyforsensitivegroup,
                    186..<305: .unhealthy,
                    305..<605: .veryunhealthy,
                    605..<1005: .hazardous,
                ],
                Constants.AirIndexTypes.no2: [
                    0..<54: .good,
                    54..<101: .moderate,
                    101..<361: .unhealthyforsensitivegroup,
                    361..<650: .unhealthy,
                    650..<1250: .veryunhealthy,
                    1250..<2050: .hazardous,
                ],
            ]

            for (range, airStatus) in rangeMaps[airIndexType] ?? [:] {
                if range.contains(value) {
                    return airStatus
                }
            }
            return .unknown
        }
    }

    enum LinkPages: CaseIterable, Identifiable {
        case aqi
        case pm25
        case pm10
        case o3
        case co
        case so2
        case no2
        case partner
        case feedback

        var id: String { url.absoluteString }

        var url: URL {
            switch self {
            case .aqi:
                return URL(string: "https://en.wikipedia.org/wiki/Air_quality_index")!
            case .pm25:
                return URL(string: "https://en.wikipedia.org/wiki/Particulates#Size,_shape_and_solubility_matter?pm25")!
            case .pm10:
                return URL(string: "https://en.wikipedia.org/wiki/Particulates#Size,_shape_and_solubility_matter?pm10")!
            case .o3:
                return URL(string: "https://en.wikipedia.org/wiki/Ozone")!
            case .co:
                return URL(string: "https://en.wikipedia.org/wiki/Carbon_monoxide")!
            case .so2:
                return URL(string: "https://en.wikipedia.org/wiki/Sulfur_dioxide")!
            case .no2:
                return URL(string: "https://en.wikipedia.org/wiki/Nitrogen_dioxide")!
            case .partner:
                return URL(string: "https://en.wikipedia.org/wiki/Air_quality_index?partner")!
            case .feedback:
                return URL(string: "https://en.wikipedia.org/wiki/Air_quality_index?partner")!
            }
        }

        var title: String {
            switch self {
            case .aqi:
                return "AQI"
            case .pm25:
                return "PM25"
            case .pm10:
                return "PM10"
            case .o3:
                return "O3"
            case .co:
                return "CO"
            case .so2:
                return "SO2"
            case .no2:
                return "NO2"
            case .partner:
                return "Interested to be our Business Partner?"
            case .feedback:
                return "Feedback / Contact us"
            }
        }
    }
}
