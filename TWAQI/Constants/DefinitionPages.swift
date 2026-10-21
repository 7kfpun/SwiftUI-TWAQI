//
//  DefinitionPages.swift
//  TWAQI
//
//  Created by kf on 9/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

enum DefinitionPages: String, CaseIterable, Identifiable {
    case aqi
    case pm25
    case pm10
    case o3
    case co
    case so2
    case no2

    var id: String { rawValue }

    /// The index this page explains, for its unit and colour bands.
    var airIndexType: AirIndexTypes {
        AirIndexTypes(rawValue: rawValue) ?? .aqi
    }

    /// Wikipedia in the reader's language, for anyone who wants more depth.
    var url: URL {
        let article: String
        if Locale.isChinese {
            switch self {
            case .aqi: article = "空氣品質指標"
            case .pm25: article = "細懸浮微粒"
            case .pm10: article = "懸浮粒子"
            case .o3: article = "臭氧"
            case .co: article = "一氧化碳"
            case .so2: article = "二氧化硫"
            case .no2: article = "二氧化氮"
            }
        } else {
            switch self {
            case .aqi: article = "Air_quality_index"
            case .pm25: article = "Particulates"
            case .pm10: article = "Particulates"
            case .o3: article = "Tropospheric_ozone"
            case .co: article = "Carbon_monoxide"
            case .so2: article = "Sulfur_dioxide"
            case .no2: article = "Nitrogen_dioxide"
            }
        }
        let host = Locale.isChinese ? "zh.wikipedia.org" : "en.wikipedia.org"
        let path = article.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? article
        return URL(string: "https://\(host)/wiki/\(path)")!
    }

    /// The page's sections, in reading order. The AQI is a scale rather than a
    /// pollutant, so it has no sources or health section of its own: its bands
    /// carry the health advice.
    var sections: [(header: LocalizedStringKey, body: LocalizedStringKey)] {
        let keys = self == .aqi
            ? ["what", "measure", "tips"]
            : ["what", "sources", "health", "measure", "tips"]
        return keys.map { key in
            (LocalizedStringKey("Guide.section_\(key)"), LocalizedStringKey("Guide.\(rawValue).\(key)"))
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .aqi:
            return "AirIndex.meaning_aqi"
        case .pm25:
            return "AirIndex.meaning_pm25"
        case .pm10:
            return "AirIndex.meaning_pm10"
        case .o3:
            return "AirIndex.meaning_o3"
        case .co:
            return "AirIndex.meaning_co"
        case .so2:
            return "AirIndex.meaning_so2"
        case .no2:
            return "AirIndex.meaning_no2"
        }
    }
}
