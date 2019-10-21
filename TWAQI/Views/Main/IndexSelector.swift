//
//  IndexSelector.swift
//  TWAQI
//
//  Created by kf on 1/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct IndexSelector: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Constants.AirIndexTypes.allCases, id: \.self) {airIndex in
                    Button(action: {
                        self.settings.airIndexTypeSelected = airIndex
                    }) {
                        Text(airIndex.toString())
                            .foregroundColor(
                                self.settings.airIndexTypeSelected == airIndex ? Color(0x5AC8FA) : Color.black
                            )
                            .fontWeight(.regular)
                            .padding(.vertical)
                            .frame(width: 55)
                            .padding(.horizontal)
                            .background(Color.white)
                            .cornerRadius(40)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct IndexSelector_Previews: PreviewProvider {
    static var previews: some View {
        IndexSelector()
            .previewLayout(.fixed(width: 600, height: 100))
    }
}
