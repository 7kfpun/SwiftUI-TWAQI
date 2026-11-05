//
//  MapHome.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreGraphics
import Foundation

/// Where the map opens before the user has ever moved it, and where the
/// "default location" button returns to.
///
/// Mirrors the supported country (`Country.supportedId`) from the countries
/// endpoint. The button prefers the API's values once loaded; these are the
/// fallback for first launch, before any network call has returned.
enum MapHome {
    static let latitude = 23.49
    static let longitude = 120.96
    static let zoom: Float = 7.9
}
