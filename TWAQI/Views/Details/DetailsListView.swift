//
//  DetailsListView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct DetailsListView: View {

    @State private var searchText = ""

    let locations = [
        Location(name: "Taipei City", localName: "臺北市"),
        Location(name: "New Taipei City", localName: "新北市"),
        Location(name: "Keelung City", localName: "基隆市"),
        Location(name: "Taoyuan City", localName: "桃園市"),
        Location(name: "Hsinchu County", localName: "新竹縣"),
        Location(name: "Hsinchu City", localName: "新竹市"),
        Location(name: "Ilan County", localName: "宜蘭縣"),
        Location(name: "Miaoli County", localName: "苗栗縣"),
        Location(name: "Kinmen County", localName: "金門縣"),
        Location(name: "Taichung City", localName: "臺中市"),
        Location(name: "Changhua County", localName: "彰化縣"),
        Location(name: "Hualien County", localName: "花蓮縣"),
        Location(name: "Nantou County", localName: "南投縣"),
        Location(name: "Yunlin County", localName: "雲林縣"),
        Location(name: "Penghu County", localName: "澎湖縣"),
        Location(name: "Chiayi County", localName: "嘉義縣"),
        Location(name: "Chiayi City", localName: "嘉義市"),
        Location(name: "Tainan City", localName: "臺南市"),
        Location(name: "Taitung County", localName: "臺東縣"),
        Location(name: "Kaohsiung City", localName: "高雄市"),
        Location(name: "Pingtung County", localName: "屏東縣")
    ]

    var body: some View {
        NavigationView {
            VStack {
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                List{
                    ForEach(locations.filter{$0.name.hasPrefix(searchText) || searchText == ""}, id:\.self) {location in

                        NavigationLink (destination: DetailsView(location: location)) {
                            DetailsRow(location: location)
                        }
                    }
                }
            }
            .navigationBarTitle("Details")
        }
    }
}

struct DetailsListView_Previews: PreviewProvider {
    static var previews: some View {
        DetailsListView()
    }
}
