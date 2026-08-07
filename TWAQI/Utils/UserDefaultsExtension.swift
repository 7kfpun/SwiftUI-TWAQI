//
//  UserDefaultsExtension.swift
//  TWAQI
//
//  Created by kf on 18/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

extension UserDefaults {
    open func setStruct<T: Codable>(_ value: T?, forKey defaultName: String) {
        let data = try? JSONEncoder().encode(value)
        set(data, forKey: defaultName)
    }

    open func structData<T>(_ type: T.Type, forKey defaultName: String) -> T? where T: Decodable {
        guard let encodedData = data(forKey: defaultName) else {
            return nil
        }

        // Cached JSON written by an older build may no longer match the type.
        // Returning nil lets the caller fall back to its default rather than
        // trapping on every launch until the app is reinstalled.
        return try? JSONDecoder().decode(type, from: encodedData)
    }

    open func setStructArray<T: Codable>(_ value: [T], forKey defaultName: String) {
        let data = value.map { try? JSONEncoder().encode($0) }

        set(data, forKey: defaultName)
    }

    open func structArrayData<T>(_ type: T.Type, forKey defaultName: String) -> [T] where T: Decodable {
        guard let encodedData = array(forKey: defaultName) as? [Data] else {
            return []
        }

        return encodedData.map { try! JSONDecoder().decode(type, from: $0) }
    }
}
