//
//  CountryListView.swift
//  watch Extension
//
//  Created by kf on 7/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct CountryListView: View {
    let defaults = UserDefaults.standard

    let countries: Countries = [
        Country(
            id: 0,
            code: "twn",
            lat: 0,
            lon: 0,
            zoom: 0,
            name: "Taiwan",
            nameLocal: "台灣"
        ),
        Country(
            id: 1,
            code: "hkg",
            lat: 0,
            lon: 0,
            zoom: 0,
            name: "Hong Kong",
            nameLocal: "香港"
        ),
        Country(
            id: 2,
            code: "tha",
            lat: 0,
            lon: 0,
            zoom: 0,
            name: "Thailand",
            nameLocal: "泰國"
        ),
        Country(
            id: 3,
            code: "ind",
            lat: 0,
            lon: 0,
            zoom: 0,
            name: "India",
            nameLocal: "印度"
        ),
    ]

    var body: some View {
        List {
            ForEach(countries, id: \.self) {country in
                NavigationLink(
                    destination: StationListView(country: country)) {
                        Button(action: {
                            print(country.nameLocal)
                            ComplicationManager.reloadComplications()
                            self.defaults.setStruct(country, forKey: "closestCountry")
                        }) {
                            Text(Locale.isChinese ? country.nameLocal : country.name)
                        }
                }
            }
        }
    }
}

struct CountryListView_Previews: PreviewProvider {
    static var previews: some View {
        CountryListView()
    }
}
