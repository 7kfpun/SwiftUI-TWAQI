//
//  LinkPages.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

enum LinkPages: CaseIterable, Identifiable {
    case partner
    case feedback
    case beta

    var id: String { url.absoluteString }

    var url: URL {
        switch self {
        case .feedback:
            return URL(string: getEnv(Locale.isChinese ? "FeedbackUrlZh" : "FeedbackUrlEn")!)!
        case .partner:
            return URL(string: getEnv(Locale.isChinese ? "PartnerUrlZh" : "PartnerUrlEn")!)!
        case .beta:
            return URL(string: getEnv("BetaTesterUrl")!)!
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .feedback:
            return "Help.feedback_or_contact_us"
        case .partner:
            return "Help.interested_to_be_our_business_partner"
        case .beta:
            return "Help.interested_to_be_our_beta_tester"
        }
    }
}
