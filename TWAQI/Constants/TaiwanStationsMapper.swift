//
//  TaiwanStationsMapper.swift
//  TWAQI
//
//  Created by kf on 5/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct TaiwanStationMapper {
    var dictionary: [String: String] {
        return [
            "Taitung": "61",
            "Tainan": "62",
            "Taixi": "63",
            "Guanyin": "64",
            "Guanshan": "65",
            "Fengyuan": "66",
            "Longtan": "67",
            "Toufen": "68",
            "Qiaotou": "69",
            "Xianxi": "70",
            "Chaozhou": "71",
            "Fengshan": "72",
            "Changhua": "73",
            "Chiayi": "74",
            "Wanhua": "75",
            "Wanli": "76",
            "Nanzi": "77",
            "Xinying": "78",
            "Xingang": "79",
            "Xinzhuang": "80",
            "Xindian": "81",
            "Hsinchu": "82",
            "Yangming": "83",
            "Cailiao": "84",
            "Shanhua": "85",
            "Hukou": "86",
            "Fuxing": "87",
            "Mailiao": "88",
            "Tamsui": "89",
            "Lunbei": "90",
            "Keelung": "91",
            "Matsu": "92",
            "Magong": "93",
            "Taoyuan": "94",
            "Puli": "95",
            "Miaoli": "96",
            "Meinong": "97",
            "Hengchun": "98",
            "Pingtung": "99",
            "Nantou": "100",
            "Qianzhen": "101",
            "Qianjin": "102",
            "Kinmen": "103",
            "Hualien": "104",
            "Songshan": "105",
            "Banqiao": "106",
            "Linyuan": "107",
            "Linkou": "108",
            "Zhongming": "109",
            "Yilan": "110",
            "Shalu": "111",
            "Xitun": "112",
            "Zhudong": "113",
            "Zhushan": "114",
            "Xizhi": "115",
            "Puzi": "116",
            "Annan": "117",
            "Yonghe": "118",
            "Pingzhen": "119",
            "Zuoying": "120",
            "Guting": "121",
            "Dongshan": "122",
            "Douliu": "123",
            "Renwu": "124",
            "Zhongli": "125",
            "Zhongshan": "126",
            "Xiaogang": "127",
            "Daliao": "128",
            "Dayuan": "129",
            "Dali": "130",
            "Datong": "131",
            "Shilin": "132",
            "Tucheng": "133",
            "Sanyi": "134",
            "Sanchong": "135",
            "Erlin": "136",
            "FugueiCape": "137",
        ]
    }

    func toStationId(name: String) -> String {
        return dictionary[name] ?? ""
    }
}
