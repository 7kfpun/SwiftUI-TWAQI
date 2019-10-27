//
//  Constants.swift
//  TWAQI
//
//  Created by kf on 19/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

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

        func getDescription() -> String {
            let units = [
                "aqi": "Air quality index",
                "pm25": "Particulates",
                "pm10": "Particulates",
                "o3": "Ozone",
                "co": "Carbon monoxide",
                "so2": "Sulfur dioxide",
                "no2": "Nitrogen dioxide",
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

        func toString() -> String {
            let readableStrings = [
                "good": "Good",
                "moderate": "Moderate",
                "unhealthyforsensitivegroup": "Unhealthy for sensitive groups",
                "unhealthy": "Unhealthy",
                "veryunhealthy": "Very unhealthy",
                "hazardous": "Hazardous",
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

        func getGeneralPublicGuidance() -> String {
            let texts = [
                "good": "Enjoy your usual outdoor activities",
                "moderate": "Enjoy your usual outdoor activities",
                "unhealthyforsensitivegroup": "Consider reducing outdoor activities",
                "unhealthy": "Should reduce physical exertion, particularly outdoors",
                "veryunhealthy": "Reduce outdoor activities",
                "hazardous": "Avoid outdoor activities and keep doors and windows closed",
            ]
            return texts[self.rawValue] ?? ""
        }

        func getSensitivePublicGuidance() -> String {
            let texts = [
                "good": "Enjoy your usual outdoor activities",
                "moderate": "Can still be active outside",
                "unhealthyforsensitivegroup": "Reduce physical exertion and outdoor activities",
                "unhealthy": "Stay indoors and reduce physical exertion",
                "veryunhealthy": "Stay indoors and reduce physical exertion",
                "hazardous": "Stay indoors and avoid physical exertion",
            ]
            return texts[self.rawValue] ?? ""
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
                    0..<4.5: .good,
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

            for (range, airStatus) in rangeMaps[Constants.AirIndexTypes.aqi] ?? [:] {
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
