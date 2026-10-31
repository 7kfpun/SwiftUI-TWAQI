//
//  SettingsRowViewModel.swift
//  TWAQI
//
//  Created by kf on 30/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

@MainActor
class SettingsRowViewModel: ObservableObject {
    /// Alerts can be on for at most this many stations.
    static let maxStations = 2

    let station: Station

    /// Guards the write-back loop while stored values are applied.
    private var isApplyingStoredSettings = false

    /// MOENV SiteId of this station's cam, stored with its Directus alerts.
    private var siteId: String?

    private var restored: AnyCancellable?

    /// The two-station limit is reached: switches that are off stay off.
    @Published var isDisabled: Bool = false

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
        self.stationSetting = .off

        StationCamStore.shared.cams { [weak self] cams in
            self?.siteId = StationCamMatcher.match(name: station.nameLocal, lat: station.lat, lon: station.lon, in: cams)?.siteId
        }

        load()

        // A reinstall's alerts arrive from Directus after the page may have
        // opened.
        restored = DirectusPushMirror.shared.$restoredAt
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
    }

    private func load() {
        let alerts = DirectusPushMirror.shared.alerts(stationId: station.id)
        isApplyingStoredSettings = true
        if StationAlerts(stationSetting) != alerts {
            stationSetting = StationAlertSetting(alerts)
        }
        isApplyingStoredSettings = false
        updateLimit()
    }

    private func save(_ setting: StationAlertSetting) {
        DirectusPushMirror.shared.stationChanged(stationId: station.id, siteId: siteId, alerts: StationAlerts(setting))
        updateLimit()
    }

    private func updateLimit() {
        isDisabled = DirectusPushMirror.shared.stationIdsWithAlerts.count >= Self.maxStations
    }
}
