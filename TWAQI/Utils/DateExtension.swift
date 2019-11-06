//
//  DateExtension.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

extension Date {
    static var currentTimeStamp: Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
