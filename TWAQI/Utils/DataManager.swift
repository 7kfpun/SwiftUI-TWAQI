//
//  DataManager.swift
//  TWAQI
//
//  Created by kf on 19/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct DataManager {
    static func getDataFromFileWithSuccess(success: (_ data: Data?) -> Void) {
        guard let filePathURL = Bundle.main.url(forResource: "stations", withExtension: "json") else {
            success(nil)
            return
        }

        do {
            let data = try Data(contentsOf: filePathURL, options: .uncached)
            success(data)
        } catch {
            fatalError()
        }
    }
}
