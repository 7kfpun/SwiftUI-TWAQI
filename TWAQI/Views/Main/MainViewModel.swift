//
//  MainViewModel.swift
//  TWAQI
//
//  Created by kf on 2/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class MainViewModel: ObservableObject {

    @Published var isCustomAdLoading: Bool = true

    var isShowCustomAd: Bool = false
    var customAd: CustomAd?

    private(set) lazy var getCustomAd: () -> Void = {
        APIManager.getCustomAd(position: "main") { result in
            switch result {
            case .success(let customAd):
                self.customAd = customAd
                self.isShowCustomAd = true
            case .failure(let error):
                print(error.localizedDescription)
                self.isShowCustomAd = false
            }

            self.isCustomAdLoading = false
        }
    }
}
