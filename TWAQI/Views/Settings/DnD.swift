//
//  DnD.swift
//  TWAQI
//
//  Created by kf on 1/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DnD: View {
    @State private var isDnDEnable = true

    var body: some View {
        VStack {
            Toggle(isOn: $isDnDEnable) {
                Text("Do not disturb")
                    .bold()
            }
            .padding(.vertical)

            if isDnDEnable {
                VStack {
                    HStack {
                        Text("Start Date")
                            .fontWeight(.light)
                        Spacer()
                        Text("10:00 PM")
                            .fontWeight(.light)
                    }

                    HStack {
                        Text("End Date")
                            .fontWeight(.light)
                        Spacer()
                        Text("8:30 AM")
                            .fontWeight(.light)
                    }
                    .padding(.vertical)
                }
            }
        }
        .padding(.horizontal)
        .background(Color(0xEEEEEE))
    }
}

struct DnD_Previews: PreviewProvider {
    static var previews: some View {
        DnD()
    }
}
