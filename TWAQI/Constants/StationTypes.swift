//
//  StationTypes.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import SwiftUI

/// `station_type` from `/v1/current-pollutants`. Newer micro-sensor stations
/// report an empty string, so `unknown` is a normal case, not an error.
enum StationTypes: String, CaseIterable, Hashable {
    case general = "GENERAL"
    case traffic = "TRAFFIC"
    case industrial = "INDUSTRIAL"
    case background = "BACKGROUND"
    case nationalPark = "NATIONAL-park"
    case other = "OTHER"
    case unknown = ""

    init(apiValue: String?) {
        self = StationTypes(rawValue: apiValue ?? "") ?? .unknown
    }

    func toString() -> LocalizedStringKey {
        let readableStrings = [
            "GENERAL": "StationType.general" as LocalizedStringKey,
            "TRAFFIC": "StationType.traffic" as LocalizedStringKey,
            "INDUSTRIAL": "StationType.industrial" as LocalizedStringKey,
            "BACKGROUND": "StationType.background" as LocalizedStringKey,
            "NATIONAL-park": "StationType.national_park" as LocalizedStringKey,
            "OTHER": "StationType.other" as LocalizedStringKey,
        ]
        return readableStrings[self.rawValue] ?? ""
    }

    func getIcon() -> String {
        switch self {
        case .general: return "building.2"
        case .traffic: return "car"
        case .industrial: return "smoke"
        case .background: return "leaf"
        case .nationalPark: return "tree"
        case .other, .unknown: return "mappin.and.ellipse"
        }
    }

    /// `unknown` carries no information worth showing.
    var isDisplayable: Bool {
        self != .unknown
    }
}
