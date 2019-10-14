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

    let stationGroups = [
        StationGroup(name: "Lianjiang County", localName: "連江縣", stations: [
            Station(
                name: "Matsu",
                localName: "馬祖",
                lon: 119.949875,
                lat: 26.160469,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=75&type=l"
            ),
        ]),
        StationGroup(name: "Taipei City", localName: "臺北市", stations: [
            Station(
                name: "Yangming",
                localName: "陽明",
                lon: 121.529583,
                lat: 25.182722,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=64&type=l"
            ),
            Station(
                name: "Songshan",
                localName: "松山",
                lon: 121.578611,
                lat: 25.050000
            ),
            Station(
                name: "Wanhua",
                localName: "萬華",
                lon: 121.507972,
                lat: 25.046503,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=13&type=l"
            ),
            Station(
                name: "Yangming",
                localName: "陽明",
                lon: 121.529583,
                lat: 25.182722,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=64&type=l"
            ),
            Station(
                name: "Songshan",
                localName: "松山",
                lon: 121.578611,
                lat: 25.050000
            ),
            Station(
                name: "Guting",
                localName: "古亭",
                lon: 121.529556,
                lat: 25.020608
            ),
            Station(
                name: "Zhongshan",
                localName: "中山",
                lon: 121.526528,
                lat: 25.062361
            ),
            Station(
                name: "Datong",
                localName: "大同",
                lon: 121.513311,
                lat: 25.063200
            ),
            Station(
                name: "Shilin",
                localName: "士林",
                lon: 121.515389,
                lat: 25.105417,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=11&type=l"
            ),
        ]),
        StationGroup(name: "New Taipei City", localName: "新北市", stations: [
            Station(
                name: "Wanli",
                localName: "萬里",
                lon: 121.689881,
                lat: 25.179667
            ),
            Station(
                name: "Xinzhuang",
                localName: "新莊",
                lon: 121.432500,
                lat: 25.037972,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=7&type=l"
            ),
            Station(
                name: "Xindian",
                localName: "新店",
                lon: 121.537778,
                lat: 24.977222,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=4&type=l"
            ),
            Station(
                name: "Cailiao",
                localName: "菜寮",
                lon: 121.481028,
                lat: 25.068950
            ),
            Station(
                name: "Tamsui",
                localName: "淡水",
                lon: 121.449239,
                lat: 25.164500
            ),
            Station(
                name: "Banqiao",
                localName: "板橋",
                lon: 121.458667,
                lat: 25.012972
            ),
            Station(
                name: "Linkou",
                localName: "林口",
                lon: 121.376869,
                lat: 25.077197,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=9&type=l"
            ),
            Station(
                name: "Xizhi",
                localName: "汐止",
                lon: 121.6405878,
                lat: 25.0658384,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=2&type=l"
            ),
            Station(
                name: "Yonghe",
                localName: "永和",
                lon: 121.516306,
                lat: 25.017000,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=70&type=l"
            ),
            Station(
                name: "Tucheng",
                localName: "土城",
                lon: 121.451861,
                lat: 24.982528
            ),
            Station(
                name: "Sanchong",
                localName: "三重",
                lon: 121.493806,
                lat: 25.072611
            ),
            Station(
                name: "FugueiCape",
                localName: "富貴角",
                lon: 121.565258,
                lat: 25.263783,
                imageUrl: "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=84&type=l"
            ),
        ]),
        StationGroup(name: "Keelung City", localName: "基隆市", stations: []),
        StationGroup(name: "Taoyuan City", localName: "桃園市", stations: []),
        StationGroup(name: "Hsinchu County", localName: "新竹縣", stations: []),
        StationGroup(name: "Hsinchu City", localName: "新竹市", stations: []),
        StationGroup(name: "Ilan County", localName: "宜蘭縣", stations: []),
        StationGroup(name: "Miaoli County", localName: "苗栗縣", stations: []),
        StationGroup(name: "Kinmen County", localName: "金門縣", stations: []),
        StationGroup(name: "Taichung City", localName: "臺中市", stations: []),
        StationGroup(name: "Changhua County", localName: "彰化縣", stations: []),
        StationGroup(name: "Hualien County", localName: "花蓮縣", stations: []),
        StationGroup(name: "Nantou County", localName: "南投縣", stations: []),
        StationGroup(name: "Yunlin County", localName: "雲林縣", stations: []),
        StationGroup(name: "Penghu County", localName: "澎湖縣", stations: []),
        StationGroup(name: "Chiayi County", localName: "嘉義縣", stations: []),
        StationGroup(name: "Chiayi City", localName: "嘉義市", stations: []),
        StationGroup(name: "Tainan City", localName: "臺南市", stations: []),
        StationGroup(name: "Taitung County", localName: "臺東縣", stations: []),
        StationGroup(name: "Kaohsiung City", localName: "高雄市", stations: []),
        StationGroup(name: "Pingtung County", localName: "屏東縣", stations: []),
    ]

    var body: some View {
        NavigationView {
            VStack {
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Divider()

                List {
                    if searchText.isEmpty {
                        ForEach(stationGroups, id: \.self) {stationGroup in
                            DetailsGroup(stationGroup: stationGroup)
                        }
                    } else {
                        ForEach(stationGroups, id: \.self) {stationGroup in
                            ForEach(stationGroup.stations.filter {$0.name.hasPrefix(self.searchText) || self.searchText.isEmpty}, id: \.self) {station in
                                DetailsRow(station: station)
                            }
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
