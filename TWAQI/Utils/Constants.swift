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

        static func checkStatus(value: Double) -> String {
            return "text"
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
