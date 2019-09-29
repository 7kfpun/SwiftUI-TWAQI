//
//  DetailsView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsView: View {
    var location: Location
    private var name: String
    private var localName: String

    var body: some View {
        VStack {
            Text(self.name)
            Text(self.localName)
        }
    }

    init(location: Location) {
        self.location = location
        self.name = location.name
        self.localName = location.localName
    }
}

struct DetailsView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsView(location: Location(name: "Taipei", localName: "台北"))
    }
}
