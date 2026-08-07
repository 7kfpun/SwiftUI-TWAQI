//
//  SettingsRowViewModel.swift
//  TWAQI
//
//  Created by kf on 30/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class SettingsRowViewModel: ObservableObject {
    let station: Station

    /// OneSignal tag key for this station: the English name for Taiwan,
    /// the numeric id everywhere else.
    private let notificationTagCode: String

    /// Guards the write-back loop while values fetched from OneSignal are applied.
    private var isApplyingRemoteSettings = false

    @Published var isDisabled: Bool = true

    @Published var stationSetting: OneSignalStationSetting {
        // `didSet` rather than `willSet`: the side effect must not run while
        // SwiftUI is still evaluating the view that owns the binding.
        didSet {
            guard !isApplyingRemoteSettings else { return }

            OneSignalManager.sendTags(tags: stationSetting.getTags()) { result in
                switch result {
                case .success(let result):
                    print(result)
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
    }

    init(station: Station) {
        self.station = station
        self.notificationTagCode = station.countryCode == "twn" ? station.name : "\(station.id)"

        self.stationSetting = OneSignalStationSetting(
            stationName: notificationTagCode,
            isPollutionNotificationEnabled: false,
            isCleanlinessNotificationEnabled: false
        )

        OneSignalManager.getOneSignalSettings { [weak self] result in
            // OneSignal calls back off the main thread; @Published must not be
            // mutated there.
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let settings):
                    self.isApplyingRemoteSettings = true
                    self.isDisabled = settings.stationSettings.count >= 2
                    if let remote = settings.stationSettings[self.notificationTagCode] {
                        self.stationSetting = remote
                    }
                    self.isApplyingRemoteSettings = false
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
    }
}
