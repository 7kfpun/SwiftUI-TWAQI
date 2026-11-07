//
//  TaiwanPlaceNames.swift
//  TWAQI
//
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Taiwan's counties and 368 townships with their official romanised names
/// (FOX-117): 新店區 Xindian District, 大安區 Da'an District.
///
/// The API gives a station's township in Chinese only. Machine translation
/// garbles place names (大安區 became "Daxian District"), so they are looked up
/// in a fixed table and never sent to Translation. A name the table doesn't
/// have stays in Chinese. The table itself is `TaiwanPlaceNamesTable.swift`,
/// made by `tools/make_taiwan_place_names.py`.
enum TaiwanPlaceNames {
    /// The API and MOENV write both 台 and 臺; the table uses 臺.
    static func normalise(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "台", with: "臺")
    }

    /// "新店區" → "Xindian District"; nil for a name the table doesn't have.
    static func township(_ chinese: String) -> String? {
        townships[normalise(chinese)]
    }

    /// "新北市" → "New Taipei City"; nil for a name the table doesn't have.
    static func county(_ chinese: String) -> String? {
        counties[normalise(chinese)]
    }

    /// The township in English outside Chinese UIs; the name as given in a
    /// Chinese UI or when the table doesn't know it.
    static func displayTownship(_ chinese: String) -> String {
        Locale.isChinese ? chinese : (township(chinese) ?? chinese)
    }
}
