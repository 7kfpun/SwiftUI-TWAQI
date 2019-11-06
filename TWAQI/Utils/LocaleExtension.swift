//
//  LocaleExtension.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

extension Locale {
    static var isChinese: Bool {
        guard let languageCode = Locale.current.languageCode else { return false }
        return languageCode.hasPrefix("zh")
    }
}
