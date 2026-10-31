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

    /// MOENV SiteId of this station's cam, stored with its Directus alerts.
    private var siteId: String?

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

            // Dual-write: OneSignal above stays the sender; Directus gets a
            // copy, debounced, and its failures stay out of the UI.
            mirror(stationSetting, settled: false)
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

        StationCamStore.shared.cams { [weak self] cams in
            self?.siteId = StationCamMatcher.match(name: station.nameLocal, lat: station.lat, lon: station.lon, in: cams)?.siteId
        }

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
                        // Alerts set before the dual-write reach Directus the
                        // first time their station is opened.
                        self.mirror(remote, settled: true)
                    }
                    self.isApplyingRemoteSettings = false
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
    }

    private func mirror(_ setting: OneSignalStationSetting, settled: Bool) {
        let alerts = StationAlerts(setting)
        let stationId = station.id
        let siteId = siteId
        Task { @MainActor in
            DirectusPushMirror.shared.stationChanged(stationId: stationId, siteId: siteId, alerts: alerts, settled: settled)
        }
    }
}
