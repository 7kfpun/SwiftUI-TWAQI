//
//  getEnv.swift
//  TWAQI
//
//  Created by kf on 12/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

func getEnv(_ key: String) -> String? {
    return (Bundle.main.infoDictionary?[key] as? String)?
        .replacingOccurrences(of: "\\", with: "")
}
