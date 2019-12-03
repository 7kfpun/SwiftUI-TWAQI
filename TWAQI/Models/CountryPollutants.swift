//
//  CountryPollutants.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias CountryPollutants = [CountryPollutant]

struct CountryPollutant {
    let id = UUID()
    let country: Country
    let datetime: Date
    let pollutants: Pollutants
}
