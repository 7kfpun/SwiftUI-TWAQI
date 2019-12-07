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
                id: 1,
                countryId: 1,
                countryCode: "twn",
                code: "Songshan",
                lat: 25.050000,
                lon: 121.578611,
                imageUrl: "",
                name: "Songshan",
                nameLocal: "松山"
            )
        ).environmentObject(SettingsStore()))
    }
}
