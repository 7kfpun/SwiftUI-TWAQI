//
//  SettingsRowViewModel.swift
//  TWAQI
//
//  Created by kf on 30/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

/// The two alerts a station can have, as the row shows them.
struct StationAlertSetting: Equatable {
    var isAboveEnabled = false
    var aboveThreshold: Double = 120
    var isBelowEnabled = false
    var belowThreshold: Double = 30
}

class SettingsRowViewModel: ObservableObject {
    enum Notice: Equatable {
        /// Notifications are off for the app in iOS Settings.
        case denied
        case saveFailed
    }

    let station: Station

    @Published var setting = StationAlertSetting()
    @Published var notice: Notice?

    /// What Directus holds, so only real changes are written.
    private var saved = StationAlertSetting()
    private var aboveId: Int?
    private var belowId: Int?
    /// MOENV SiteId of this station's cam, stored alongside for the cams.
    private var siteId: String?

    /// Guards the write-back while values read from Directus are applied.
    private var isApplyingRemoteSettings = false
    private var cancellables = Set<AnyCancellable>()

    init(station: Station) {
        self.station = station

        // A slider sends a value per step; save once it settles.
        $setting
            .dropFirst()
            .filter { [weak self] _ in self?.isApplyingRemoteSettings == false }
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        StationCamStore.shared.cams { [weak self] cams in
            guard let self = self else { return }
            self.siteId = StationCamMatcher.match(name: station.nameLocal, lat: station.lat, lon: station.lon, in: cams)?.siteId
        }

        Task { @MainActor [weak self] in
            await self?.load()
        }
    }

    @MainActor
    private func load() async {
        if PushManager.shared.authorization == .denied {
            notice = .denied
        }
        do {
            let subscriptions = try await PushManager.shared.subscriptions(stationId: station.id)
            var remote = StationAlertSetting()
            for subscription in subscriptions {
                switch subscription.direction {
                case .above:
                    aboveId = subscription.id
                    remote.isAboveEnabled = subscription.enabled
                    remote.aboveThreshold = subscription.threshold
                case .below:
                    belowId = subscription.id
                    remote.isBelowEnabled = subscription.enabled
                    remote.belowThreshold = subscription.threshold
                }
            }
            apply(remote)
        } catch {
            print("Loading alerts failed: \(error)")
        }
    }

    private func apply(_ remote: StationAlertSetting) {
        saved = remote
        isApplyingRemoteSettings = true
        setting = remote
        isApplyingRemoteSettings = false
    }

    private func save() {
        let wanted = setting
        Task { @MainActor in
            do {
                if wanted.isAboveEnabled != saved.isAboveEnabled || wanted.aboveThreshold != saved.aboveThreshold {
                    aboveId = try await write(id: aboveId, direction: .above, threshold: wanted.aboveThreshold, enabled: wanted.isAboveEnabled)
                    saved.isAboveEnabled = wanted.isAboveEnabled
                    saved.aboveThreshold = wanted.aboveThreshold
                }
                if wanted.isBelowEnabled != saved.isBelowEnabled || wanted.belowThreshold != saved.belowThreshold {
                    belowId = try await write(id: belowId, direction: .below, threshold: wanted.belowThreshold, enabled: wanted.isBelowEnabled)
                    saved.isBelowEnabled = wanted.isBelowEnabled
                    saved.belowThreshold = wanted.belowThreshold
                }
                notice = nil
            } catch PushError.notAuthorized {
                // The switch can't do anything without permission; put it back.
                notice = .denied
                apply(saved)
            } catch {
                print("Saving alert failed: \(error)")
                notice = .saveFailed
                apply(saved)
            }
        }
    }

    /// Nothing to write for an alert that was never on.
    @MainActor
    private func write(id: Int?, direction: PushDirection, threshold: Double, enabled: Bool) async throws -> Int? {
        if id == nil && !enabled { return nil }

        let id = try await PushManager.shared.save(PushSubscription(
            id: id,
            stationId: String(station.id),
            siteId: siteId,
            direction: direction,
            threshold: threshold,
            enabled: enabled
        ))

        TrackingManager.logEvent(eventName: "set_station_alert", parameters: [
            "stationId": station.id,
            "direction": direction.rawValue,
            "label": enabled ? "on" : "off",
            "threshold": Int(threshold),
        ])
        return id
    }
}
