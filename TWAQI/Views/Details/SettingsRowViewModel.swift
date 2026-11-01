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

    private let settings = SettingsStore()
    private var clearedObserver: NSObjectProtocol?

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

            let isOn = !StationAlerts(stationSetting).isOff
            if isOn {
                addToFavourites()
            }
            FavouriteAlerts.post(stationId: station.id, isOn: isOn)
        }
    }

    init(station: Station) {
        self.station = station
        self.notificationTagCode = FavouriteAlerts.tagCode(countryCode: station.countryCode, name: station.name, stationId: station.id)

        self.stationSetting = OneSignalStationSetting(
            stationName: notificationTagCode,
            isPollutionNotificationEnabled: false,
            isCleanlinessNotificationEnabled: false
        )

        followClears()

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
                    self.isDisabled = settings.stationSettings.count >= FavouriteAlerts.maxAlertedStations
                    if let remote = settings.stationSettings[self.notificationTagCode] {
                        self.stationSetting = remote
                        // Alerts set before the dual-write reach Directus the
                        // first time their station is opened.
                        self.mirror(remote, settled: true)
                    }
                    FavouriteAlerts.post(stationId: self.station.id, isOn: !StationAlerts(self.stationSetting).isOff)
                    self.isApplyingRemoteSettings = false
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
    }

    deinit {
        clearedObserver.map(NotificationCenter.default.removeObserver)
    }

    /// An alert switched on makes the station a favourite, so every station
    /// that can send one is in the list where it can be found and removed.
    private func addToFavourites() {
        guard !settings.savedFavouriteStations.contains(station.id) else { return }
        settings.savedFavouriteStations.append(station.id)
        TrackingManager.logEvent(eventName: "favourite_station_saved", parameters: [
            "label": "on",
            "stationId": station.id,
            "source": "alert",
        ])
    }

    /// Alerts changed elsewhere follow here, without being written back:
    /// cleared because the station left Favourites, or switched on because it
    /// was just favourited (FOX-31).
    private func followClears() {
        clearedObserver = NotificationCenter.default.addObserver(
            forName: FavouriteAlerts.changed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let isOn = FavouriteAlerts.isOn(in: notification, stationId: self.station.id)
            else { return }

            if !isOn {
                guard !StationAlerts(self.stationSetting).isOff else { return }
                self.isApplyingRemoteSettings = true
                self.stationSetting.isPollutionNotificationEnabled = false
                self.stationSetting.isCleanlinessNotificationEnabled = false
                self.isApplyingRemoteSettings = false
            } else if let setting = FavouriteAlerts.setting(in: notification),
                      StationAlerts(self.stationSetting).isOff {
                self.isApplyingRemoteSettings = true
                self.stationSetting = setting
                if let count = FavouriteAlerts.alertedStationCount(in: notification) {
                    self.isDisabled = count >= FavouriteAlerts.maxAlertedStations
                }
                self.isApplyingRemoteSettings = false
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
