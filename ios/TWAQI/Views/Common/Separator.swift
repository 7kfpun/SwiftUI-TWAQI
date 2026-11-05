//
//  Separator.swift
//  TWAQI
//
//  Created by kf on 22/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct Separator: View {
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .frame(
                    width: geometry.size.width,
                    height: 8
                )
        }
    }
}

struct Separator_Previews: PreviewProvider {
    static var previews: some View {
        Separator()
    }
}
