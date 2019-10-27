//
//  NumberExtensions.swift
//  TWAQI
//
//  Created by kf on 27/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

extension Int {
    // swiftlint:disable:next identifier_name
    func format(f: String) -> String {
        return String(format: "%\(f)d", self)
    }
}

extension Double {
    // swiftlint:disable:next identifier_name
    func format(f: String) -> String {
        return String(format: "%\(f)f", self)
    }
}
