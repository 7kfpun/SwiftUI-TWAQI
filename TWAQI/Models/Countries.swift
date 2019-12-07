//
//  Countries.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias Countries = [Country]

struct Country: Codable, Hashable {
    let id: Int
    let code: String
    let lat: Double
    let lon: Double
    let zoom: Float

    let name: String
    let nameLocal: String
}
