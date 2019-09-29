//
//  Location.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct Location: Hashable, Codable, Identifiable {
    let id = UUID()
    var name: String
    var localName: String
}
