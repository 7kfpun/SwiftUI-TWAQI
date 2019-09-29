//
//  SettingsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct SettingsRow: View {
    @State var isNotificationEnabled = false
    @State private var min: Double = 30
    @State private var max: Double = 120

    var location: Location

    var body: some View {
        VStack {
            Toggle(isOn: $isNotificationEnabled) {
                Text(location.name)
                    .bold()
                    .padding(.vertical, 15)
            }

            if (isNotificationEnabled) {
                HStack {
                    Text("Pollution therhold")
                    Spacer()
                    Text("\(max)")
                }

                Slider(value: $max, in: 0...500, step: 1)

                HStack {
                    Text("Cleanliness therhold")
                    Spacer()
                    Text("\(min)")
                }

                Slider(value: $min, in: 0...500, step: 1)
            }
        }
    }

    init(location: Location) {
        self.location = location
    }
}

struct SettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsRow(location: Location(name: "Taipei", localName: "台北"))
            SettingsRow(location: Location(name: "Taichung", localName: "台中"))
        }
        .previewLayout(.fixed(width: 400, height: 250))
    }
}
