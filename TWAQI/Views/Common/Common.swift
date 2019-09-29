//
//  Common.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

func button(for icon: String) -> some View {
    Button(action: {
        print("Help tapped!")
    }) {
        Image(systemName: icon)
            .frame(width: 60.0, height: 60.0)
            .background(Color.white)
            .foregroundColor(Color(0x5AC8FA))
            .clipShape(Circle())
            .shadow(radius: 2)
    }
}

struct Common: View {
    var body: some View {
        HStack {
            button(for: "rectangle.grid.1x2.fill")
            button(for: "square.and.arrow.up.fill")
            button(for: "tray.and.arrow.down")
            button(for: "paperplane.fill")
        }
    }
}

struct Common_Previews: PreviewProvider {
    static var previews: some View {
        Common()
    }
}
