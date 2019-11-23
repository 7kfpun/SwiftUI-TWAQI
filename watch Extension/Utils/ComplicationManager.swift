//
//  ComplicationManager.swift
//  watch Extension
//
//  Created by kf on 24/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct ComplicationManager {
    static func reloadComplications() {
        if let complications: [CLKComplication] = CLKComplicationServer.sharedInstance().activeComplications {
            if !complications.isEmpty {
                for complication in complications {
                    CLKComplicationServer.sharedInstance().reloadTimeline(for: complication)
                    print("Reloading complication \(complication.description)...")
                }
            }
        }
    }
}
