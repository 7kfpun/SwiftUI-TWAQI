//
//  Countries.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

typealias Countries = [Country]

struct Country: Codable, Hashable {
    let id: Int
    let code: String
    let lat: Double
    let lon: Double
    let zoom: Float

    let name: String
    let nameLocal: String
}

extension Country {
    /// The app only supports one country end-to-end — station search, 24-hour
    /// history, and the per-station notification tags all assume it. Markers
    /// from other countries are still drawn for regional context, but they are
    /// muted and cannot be opened.
    static let supportedId = 3

    var isSupported: Bool {
        id == Country.supportedId
    }

    /// The API occasionally returns placeholder rows with no name and null
    /// island coordinates. They must not participate in nearest-country search.
    var hasValidLocation: Bool {
        !(lat == 0 && lon == 0)
    }

    /// Never blank: falls back through the other language, then the code.
    var displayName: String {
        let preferred = Locale.isChinese ? nameLocal : name
        if !preferred.isEmpty { return preferred }
        let alternate = Locale.isChinese ? name : nameLocal
        if !alternate.isEmpty { return alternate }
        return code.uppercased()
    }
}
