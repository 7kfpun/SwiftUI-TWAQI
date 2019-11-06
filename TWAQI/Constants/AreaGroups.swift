//
//  AreaGroups.swift
//  TWAQI
//
//  Created by kf on 6/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import SwiftUI

enum AreaGroups: String, CaseIterable {
    case north
    case chumiao
    case central
    case yunchianan
    case kaoping
    case yilan
    case huatun
    case matsu
    case kinmen
    case magong

    func getKey() -> String {
        let readableStrings = [
            "north": "北部",
            "chumiao": "竹苗",
            "central": "中部",
            "yunchianan": "雲嘉南",
            "kaoping": "高屏",
            "yilan": "宜蘭",
            "huatun": "花東",
            "matsu": "馬祖",
            "kinmen": "金門",
            "magong": "澎湖",
        ]
        return readableStrings[self.rawValue] ?? ""
    }

    func toString() -> LocalizedStringKey {
        let readableStrings = [
            "north": "AreaGroup.north" as LocalizedStringKey,
            "chumiao": "AreaGroup.chumiao" as LocalizedStringKey,
            "central": "AreaGroup.central" as LocalizedStringKey,
            "yunchianan": "AreaGroup.yunchianan" as LocalizedStringKey,
            "kaoping": "AreaGroup.kaoping" as LocalizedStringKey,
            "yilan": "AreaGroup.yilan" as LocalizedStringKey,
            "huatun": "AreaGroup.huatun" as LocalizedStringKey,
            "matsu": "AreaGroup.matsu" as LocalizedStringKey,
            "kinmen": "AreaGroup.kinmen" as LocalizedStringKey,
            "magong": "AreaGroup.magong" as LocalizedStringKey,
        ]
        return readableStrings[self.rawValue] ?? ""
    }
}
