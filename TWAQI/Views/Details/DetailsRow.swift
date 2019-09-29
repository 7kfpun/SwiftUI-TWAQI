//
//  DetailsRow.swift
//  TWAQI
//
//  Created by kf on 29/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsRow: View {
    var location: Location

    var body: some View {
        HStack {
            Text(location.name)
                .padding(.vertical, 15)
        }
    }
}

struct DetailsRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DetailsRow(location: Location(name: "Taipei", localName: "台北"))
            DetailsRow(location: Location(name: "Taichung", localName: "台中"))
        }
        .previewLayout(.fixed(width: 300, height: 50))
    }
}
