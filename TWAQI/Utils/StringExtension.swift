//
//  StringExtension.swift
//  TWAQI
//
//  Created by kf on 23/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}
