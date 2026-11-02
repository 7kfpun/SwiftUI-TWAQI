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
    /// Whether the card knows what OneSignal holds, so its switches mean
    /// something.
    enum AlertsState: Equatable {
        /// Reading OneSignal: switches locked, no cap message yet.
        case checking
        case ready
        /// OneSignal failed or didn't answer (offline, not registered yet).
        case unavailable
    }

    let station: Station

    /// OneSignal tag key for this station: the English name for Taiwan,
    /// the numeric id everywhere else.
    private let notificationTagCode: String

    /// Guards the write-back loop while values fetched from OneSignal are applied.
    private var isApplyingRemoteSettings = false

    /// MOENV SiteId of this station's cam, stored with its Directus alerts.
    private var siteId: String?

    /// The alerts OneSignal last took, read or written: where the switches
    /// go back to when a write fails.
    private var confirmedSetting: OneSignalStationSetting

    /// Counts writes, so only the latest one's answer moves the switches.
    private var writeGeneration = 0

    private let settings = SettingsStore()
    private var changesObserver: NSObjectProtocol?

    @Published private(set) var alertsState: AlertsState = .checking

    /// Two other stations already have alerts, so switches that are off stay
    /// locked. Only meaningful once `alertsState` is `.ready`.
    @Published private(set) var isAtCap = false

    /// The latest change didn't reach OneSignal; the switches went back.
    @Published private(set) var saveFailed = false

    @Published var stationSetting: OneSignalStationSetting {
        // `didSet` rather than `willSet`: the side effect must not run while
        // SwiftUI is still evaluating the view that owns the binding.
        didSet {
            guard !isApplyingRemoteSettings else { return }
            save(stationSetting)
        }
    }

    init(station: Station) {
        self.station = station
        self.notificationTagCode = FavouriteAlerts.tagCode(countryCode: station.countryCode, name: station.name, stationId: station.id)

        let off = OneSignalStationSetting(
            stationName: notificationTagCode,
            isPollutionNotificationEnabled: false,
            isCleanlinessNotificationEnabled: false
        )
        self.stationSetting = off
        self.confirmedSetting = off

        followChanges()

        StationCamStore.shared.cams { [weak self] cams in
            self?.siteId = StationCamMatcher.match(name: station.nameLocal, lat: station.lat, lon: station.lon, in: cams)?.siteId
        }

        reload()
    }

    deinit {
        changesObserver.map(NotificationCenter.default.removeObserver)
    }

    /// Reads OneSignal for this station's alerts and the cap.
    func reload() {
        alertsState = .checking
        OneSignalManager.getOneSignalSettings { [weak self] result in
            // OneSignal calls back off the main thread; @Published must not be
            // mutated there.
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let settings):
                    self.isApplyingRemoteSettings = true
                    self.isAtCap = FavouriteAlerts.isAtCap(settings, excluding: self.notificationTagCode)
                    if let remote = settings.stationSettings[self.notificationTagCode] {
                        self.stationSetting = remote
                        // Read from OneSignal, so already there: alerts set
                        // before the dual-write reach Directus the first time
                        // their station is opened.
                        FavouriteAlerts.Services.live.mirror(self.station.id, self.siteId, StationAlerts(remote), true)
                    }
                    self.confirmedSetting = self.stationSetting
                    self.isApplyingRemoteSettings = false
                    self.saveFailed = false
                    self.alertsState = .ready
                    FavouriteAlerts.post(stationId: self.station.id, isOn: !StationAlerts(self.stationSetting).isOff)
                case .failure(let error):
                    print(error.localizedDescription)
                    self.alertsState = .unavailable
                }
            }
        }
    }

    /// A switch or slider moved: OneSignal first, the Directus copy once
    /// OneSignal has it. If OneSignal doesn't take the latest change, the
    /// switches go back to what it holds and the card says so.
    private func save(_ setting: OneSignalStationSetting) {
        saveFailed = false
        let isOn = !StationAlerts(setting).isOff
        if isOn {
            addToFavourites()
        }
        FavouriteAlerts.post(stationId: station.id, isOn: isOn)

        writeGeneration += 1
        let generation = writeGeneration
        FavouriteAlerts.write(
            setting,
            stationId: station.id,
            siteId: siteId,
            isCurrent: { [weak self] in self?.writeGeneration == generation }
        ) { [weak self] taken in
            guard let self = self, self.writeGeneration == generation else { return }
            if taken {
                self.confirmedSetting = setting
            } else {
                self.revert()
            }
        }
    }

    private func revert() {
        saveFailed = true
        isApplyingRemoteSettings = true
        stationSetting = confirmedSetting
        isApplyingRemoteSettings = false
        FavouriteAlerts.post(stationId: station.id, isOn: !StationAlerts(confirmedSetting).isOff)
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
    private func followChanges() {
        changesObserver = NotificationCenter.default.addObserver(
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
                self.confirmedSetting = self.stationSetting
                self.isApplyingRemoteSettings = false
            } else if let setting = FavouriteAlerts.setting(in: notification),
                      StationAlerts(self.stationSetting).isOff {
                self.isApplyingRemoteSettings = true
                self.stationSetting = setting
                self.confirmedSetting = setting
                if let count = FavouriteAlerts.alertedStationCount(in: notification) {
                    // The count includes this station.
                    self.isAtCap = count - 1 >= FavouriteAlerts.maxAlertedStations
                    self.alertsState = .ready
                }
                self.isApplyingRemoteSettings = false
            }
        }
    }
}
