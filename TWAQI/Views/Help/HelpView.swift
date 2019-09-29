//
//  HelpView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        NavigationView {
            List {
                HStack {
                    Text("Hello")
                    Spacer()
                    Text("1")
                }
                .padding(.vertical, 12)

                HStack {
                    Text("Hello")
                    Spacer()
                    Text("2")
                }
                .padding(.vertical, 12)
            }
            .navigationBarTitle("Help")
            .navigationBarItems(trailing:
                Button(action: {
                    print("Help tapped!")
                }) {
                    Text("Help")
                }
            )
        }
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}
