//
//  HostingController.swift
//  watch Extension
//
//  Created by kf on 17/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import WatchKit
import Foundation
import SwiftUI

class HostingController: WKHostingController<AnyView> {
    override var body: AnyView {
        return AnyView(ContentView(
            station: Station(
                name: "Matsu",
                nameLocal: "馬祖",
                lat: 26.160469,
                lon: 119.949875,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
            )
        ).environmentObject(SettingsStore()))
    }
}
