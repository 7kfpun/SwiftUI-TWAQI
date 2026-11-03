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

    /// Guards the write-back loop while stored or announced values are applied.
    private var isApplyingStoredSettings = false

    /// MOENV SiteId of this station's cam, stored with its Directus alerts.
    private var siteId: String?

    private let settings = SettingsStore()
    private var changesObserver: NSObjectProtocol?

    /// `FavouriteAlerts.maxAlertedStations` other stations already have
    /// alerts, so switches that are off stay locked.
    @Published private(set) var isAtCap = false {
        didSet { logAlertLimitIfShown() }
    }

    /// `alert_limit_shown` is logged once per station page, not on every read.
    private var loggedAlertLimit = false

    @Published var stationSetting: StationAlertSetting {
        // `didSet` rather than `willSet`: the side effect must not run while
        // SwiftUI is still evaluating the view that owns the binding.
        didSet {
            guard !isApplyingStoredSettings else { return }
            save(stationSetting)
        }
    }

    init(station: Station) {
        self.station = station
        self.stationSetting = StationAlertSetting(DirectusPushMirror.alerts(stationId: station.id))
        self.isAtCap = FavouriteAlerts.isAtCap(alertedStationIds: FavouriteAlerts.alertedStationIds(), excluding: station.id)
        logAlertLimitIfShown()

        followChanges()

        StationCamStore.shared.cams { [weak self] cams in
            self?.siteId = StationCamMatcher.match(name: station.nameLocal, lat: station.lat, lon: station.lon, in: cams)?.siteId
        }
    }

    deinit {
        changesObserver.map(NotificationCenter.default.removeObserver)
    }

    /// A switch or slider moved: saved on the device at once, the Directus
    /// copy once the slider stops.
    private func save(_ setting: StationAlertSetting) {
        let isOn = !StationAlerts(setting).isOff
        guard FavouriteAlerts.write(setting, stationId: station.id, siteId: siteId) else {
            // Other stations reached the cap since this screen last looked
            // (another window): the switches go back off and lock.
            isApplyingStoredSettings = true
            stationSetting.isPollutionNotificationEnabled = false
            stationSetting.isCleanlinessNotificationEnabled = false
            isApplyingStoredSettings = false
            isAtCap = true
            return
        }
        if isOn {
            addToFavourites()
        }
        FavouriteAlerts.post(stationId: station.id, isOn: isOn)
    }

    /// An alert switched on makes the station a favourite, so every station
    /// that can send one is in the list where it can be found and removed.
    private func addToFavourites() {
        guard !settings.savedFavouriteStations.contains(station.id) else { return }
        settings.savedFavouriteStations.append(station.id)
        TrackingManager.logEvent(.favouriteStationSaved, parameters: [
            "label": "on",
            "stationId": station.id,
            "source": "alert",
        ])
    }

    /// Alerts changed elsewhere follow here, without being written back:
    /// cleared because the station left Favourites, switched on because it
    /// was just favourited (FOX-31) or restored after a reinstall. Any
    /// station's change can move the cap.
    private func followChanges() {
        changesObserver = NotificationCenter.default.addObserver(
            forName: FavouriteAlerts.changed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            self.isAtCap = FavouriteAlerts.isAtCap(alertedStationIds: FavouriteAlerts.alertedStationIds(), excluding: self.station.id)

            guard let isOn = FavouriteAlerts.isOn(in: notification, stationId: self.station.id) else { return }
            if !isOn {
                guard !StationAlerts(self.stationSetting).isOff else { return }
                self.isApplyingStoredSettings = true
                self.stationSetting.isPollutionNotificationEnabled = false
                self.stationSetting.isCleanlinessNotificationEnabled = false
                self.isApplyingStoredSettings = false
            } else if let setting = FavouriteAlerts.setting(in: notification),
                      StationAlerts(self.stationSetting).isOff {
                self.isApplyingStoredSettings = true
                self.stationSetting = setting
                self.isApplyingStoredSettings = false
            }
        }
    }

    /// The card is showing the station-limit note (`SettingsRow` shows it
    /// whenever other stations are at the limit).
    private func logAlertLimitIfShown() {
        guard isAtCap, !loggedAlertLimit else { return }
        loggedAlertLimit = true
        TrackingManager.logEvent(.alertLimitShown, parameters: ["stationId": station.id])
    }
}
