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

    func getColor() -> UInt32 {
        let colors = [
            "good": 0x009866,
            "moderate": 0xFEDE33,
            "unhealthyforsensitivegroup": 0xFE9833,
            "unhealthy": 0xCC0033,
            "veryunhealthy": 0x660098,
            "hazardous": 0x7E2200,
        ]
        return UInt32(colors[self.rawValue] ?? 0x676767)
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

    func getImage() -> String {
        "status_\(self.rawValue)"
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

    static func checkAirStatus(airIndexType: AirIndexTypes, value: Double) -> AirStatuses {
        let rangeMaps: [AirIndexTypes: [Range<Double>: AirStatuses]] = [
            AirIndexTypes.aqi: [
                1..<51: .good,
                51..<101: .moderate,
                101..<151: .unhealthyforsensitivegroup,
                151..<201: .unhealthy,
                201..<301: .veryunhealthy,
                301..<100*10: .hazardous,
            ],
            AirIndexTypes.pm25: [
                0.1..<15.5: .good,
                15.5..<35.5: .moderate,
                35.5..<54.5: .unhealthyforsensitivegroup,
                54.5..<150.5: .unhealthy,
                150.5..<250.5: .veryunhealthy,
                250.5..<500.5*10: .hazardous,
            ],
            AirIndexTypes.pm10: [
                1..<55: .good,
                55..<126: .moderate,
                126..<255: .unhealthyforsensitivegroup,
                255..<355: .unhealthy,
                355..<425: .veryunhealthy,
                425..<605*10: .hazardous,
            ],
            AirIndexTypes.o3: [
                1..<55: .good,
                55..<125: .moderate,
                125..<165: .unhealthyforsensitivegroup,
                165..<205: .unhealthy,
                205..<405: .veryunhealthy,
                405..<605: .hazardous,
            ],
            AirIndexTypes.co: [
                0.1..<4.5: .good,
                4.5..<9.5: .moderate,
                9.5..<12.5: .unhealthyforsensitivegroup,
                12.5..<15.5: .unhealthy,
                15.5..<30.5: .veryunhealthy,
                30.5..<50.5: .hazardous,
            ],
            AirIndexTypes.so2: [
                1..<36: .good,
                36..<76: .moderate,
                76..<186: .unhealthyforsensitivegroup,
                186..<305: .unhealthy,
                305..<605: .veryunhealthy,
                605..<1005: .hazardous,
            ],
            AirIndexTypes.no2: [
                1..<54: .good,
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
