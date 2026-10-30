//
//  LinkPages.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

/// External pages listed under Help → Contact us. Feedback is no longer one of
/// them: it is sent in-app by `FeedbackView`.
enum LinkPages: String, CaseIterable, Identifiable {
    case partner

    var id: String { url.absoluteString }

    var url: URL {
        switch self {
        case .partner:
            return URL(string: getEnv(Locale.isChinese ? "PartnerUrlZh" : "PartnerUrlEn")!)!
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .partner:
            return "Help.interested_to_be_our_business_partner"
        }
    }
}
