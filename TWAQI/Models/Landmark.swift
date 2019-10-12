//
//  Landmark.swift
//  TWAQI
//
//  Created by kf on 12/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import MapKit

struct Landmark: Equatable {
    static func == (lhs: Landmark, rhs: Landmark) -> Bool {
        lhs.id == rhs.id
    }

    let id = UUID().uuidString
    let name: String
    let location: CLLocationCoordinate2D
    let aqi: String
}
