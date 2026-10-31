//
//  StringExtension.swift
//  TWAQI
//
//  Created by kf on 23/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

extension String {
    /// Localized in the app's language (the Help choice, else the system's).
    var localized: String {
        return NSLocalizedString(self, bundle: .appLanguage, comment: "")
    }

    func maxLength(length: Int) -> String {
        var str = self
        let nsString = str as NSString
        if nsString.length >= length {
            str = nsString.substring(with:
                NSRange(
                    location: 0,
                    length: nsString.length > length ? length : nsString.length)
            )
            str = "\(str)..."
        }
        return  str
    }
}
