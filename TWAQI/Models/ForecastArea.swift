//
//  ForecastArea.swift
//  TWAQI
//
//  Created by kf on 12/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias ForecastAreas = [ForecastArea]

struct ForecastArea: Codable, Hashable {
    let id = UUID()
    let aqi: String
    let area: String
    let content: String
    let forecastDate: String
    let majorPollutant: String
    let minorPollutant: String
    let minorPollutantAQI: String
    let publishTime: String

    private enum CodingKeys: String, CodingKey {
        case aqi = "AQI"
        case area = "Area"
        case content = "Content"
        case forecastDate = "ForecastDate"
        case majorPollutant = "MajorPollutant"
        case minorPollutant = "MinorPollutant"
        case minorPollutantAQI = "MinorPollutantAQI"
        case publishTime = "PublishTime"
    }
}
