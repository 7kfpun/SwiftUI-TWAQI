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
    let objectWillChange = ObservableObjectPublisher()

    @Published var pollutants: [Pollutant] = [] {
        willSet { self.objectWillChange.send() }
    }

    private(set) lazy var getData: () -> Void = {
        APIManager.getAQI { result in
            switch result {
            case .success(let pollutants):
                print("\(pollutants) unread messages.")
                self.pollutants = pollutants
                print("Total: \(pollutants.count), first item \(pollutants[0])")
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
