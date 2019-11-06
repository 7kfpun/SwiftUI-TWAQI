//
//  LinkPages.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

enum LinkPages: CaseIterable, Identifiable {
    case partner
    case feedback
    case aqi
    case pm25
    case pm10
    case o3
    case co
    case so2
    case no2

    var id: String { url.absoluteString }

    var url: URL {
        switch self {
        case .feedback:
            return URL(string: getEnv(Locale.isChinese ? "FeedbackUrlZh" : "FeedbackUrlEn")!)!
        case .partner:
            return URL(string: getEnv(Locale.isChinese ? "PartnerUrlZh" : "PartnerUrlEn")!)!
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
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .feedback:
            return "Help.feedback_or_contact_us"
        case .partner:
            return "Help.interested_to_be_our_business_partner"
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
        }
    }
}
