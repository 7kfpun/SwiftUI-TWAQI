//
//  LinkPages.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

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
