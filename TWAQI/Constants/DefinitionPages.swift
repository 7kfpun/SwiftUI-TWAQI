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
