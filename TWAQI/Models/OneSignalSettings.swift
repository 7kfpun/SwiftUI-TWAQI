//
//  OneSignalSettings.swift
//  TWAQI
//
//  Created by kf on 20/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct OneSignalSettings: Hashable, Codable {
    var isDndEnabled: Bool?
    var isForecastEnabled: Bool?
    var dndStartTime: Int?
    var dndEndTime: Int?
}
