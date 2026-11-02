//
//  DetailsViewModel.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class DetailsViewModel: ObservableObject {
    let settings = SettingsStore()

    var stationId: Int

    @Published var station: Station?

    /// Current conditions for this station. Carries the location detail
    /// (address, area, county, station type) and wind that the historical
    /// endpoint does not return.
    @Published var pollutant: Pollutant?

    @Published var historicalPollutants: HistoricalPollutants = []

    /// Whether the station has an alert on: from the alert controls once
    /// they have read OneSignal, else this device's last record of what it
    /// sent. Nil when neither is known yet.
    @Published private(set) var alertsOn: Bool?

    /// The station has an alert on, as far as is known.
    var hasAlerts: Bool { alertsOn == true }

    /// Unfavouriting waits on the reader: it would also turn alerts off.
    @Published var isConfirmingUnfavourite = false

    /// Why favouriting just now left the station's alerts off, when the
    /// reader can do something about it. Nil otherwise.
    @Published var favouriteAlertsHint: FavouriteAlertsHint?

    /// The station record didn't load, so there is no alerts card to show:
    /// the page shows why instead.
    @Published var stationLoadFailed = false

    /// Favourited before the station record — which says which OneSignal tag
    /// the alerts go under — had loaded: switched on once it has.
    private var enablesAlertsWhenStationLoads = false

    private var alertsObserver: NSObjectProtocol?

    /// `pollutant` is the last good reading saved, because the latest
    /// request failed.
    @Published var isShowingLastGood = false

    /// Both requests failed and there was no saved reading to show instead.
    @Published var loadFailed = false

    /// The API answered, and has no current reading for this station. Search
    /// lists every station `getStations` knows (~150), but only the ones still
    /// reporting (~84, the map's) have one; the rest are retired or offline
    /// sites whose history can be years old. Not an outage — `loadFailed` and
    /// `isShowingLastGood` cover those.
    @Published var isNotReporting = false

    /// Answers from the latest `getData`, so `loadFailed` is decided once
    /// both requests have answered. `onAppear` can fire again while the first
    /// pair is still on the wire; answers from an older pair are not counted.
    private var generation = 0
    private var answers: [Bool] = []

    /// This station's MOENV webcam, found by joining on name and position.
    @Published var cam: StationCamState = .loading

    /// MOENV's forecast for this station's 空品區, today onwards. Nil until
    /// loaded, and stays nil when there is none (offline, no match) — the
    /// screen then shows no forecast section at all.
    @Published var forecast: AreaForecast?

    init(stationId: Int, historicalPollutants: HistoricalPollutants = []) {
        self.stationId = stationId
        self.historicalPollutants = historicalPollutants
        self.alertsOn = FavouriteAlerts.locallyKnown(stationId: stationId)
        self.alertsObserver = NotificationCenter.default.addObserver(
            forName: FavouriteAlerts.changed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let isOn = FavouriteAlerts.isOn(in: notification, stationId: self.stationId) else { return }
            if self.alertsOn != isOn {
                self.alertsOn = isOn
            }
        }
    }

    deinit {
        alertsObserver.map(NotificationCenter.default.removeObserver)
    }

    private(set) lazy var getData: () -> Void = {
        // The last good reading at once, so a station opened offline — or
        // on a slow connection — is not a blank page. The request replaces it.
        if self.pollutant == nil, let saved = PollutantCache.shared.pollutant(stationId: self.stationId) {
            self.pollutant = saved
            self.findCam(name: saved.nameLocal, lat: saved.lat, lon: saved.lon)
            self.findForecast(areaLocal: saved.areaLocal, countyLocal: saved.countyLocal, title: saved.displayArea)
        }
        self.generation += 1
        let generation = self.generation
        self.answers = []
        self.loadFailed = false

        APIManager.getHistoricalPollutants(stationId: self.stationId) { result in
            switch result {
            case .success(let result):
                self.station = result["station"] as? Station
                self.stationLoadFailed = self.station == nil
                self.historicalPollutants = result["data"] as? HistoricalPollutants ?? []
                if self.enablesAlertsWhenStationLoads, self.station != nil {
                    self.enablesAlertsWhenStationLoads = false
                    self.enableAlertsForNewFavourite()
                }
                if let station = self.station {
                    self.findCam(name: station.nameLocal, lat: station.lat, lon: station.lon)
                    self.findForecast(areaLocal: station.areaLocal, countyLocal: station.countyLocal, title: station.displayArea)
                }
                self.requestFinished(failed: false, generation: generation)
            case .failure(let error):
                print(error.localizedDescription)
                self.stationLoadFailed = self.station == nil
                // Favourited while this was on the wire: say the alerts
                // couldn't be switched on, rather than wait in silence.
                if self.enablesAlertsWhenStationLoads, self.station == nil {
                    self.enablesAlertsWhenStationLoads = false
                    self.favouriteAlertsHint = .notChanged
                }
                self.requestFinished(failed: true, generation: generation)
            }
        }

        APIManager.getCurrentPollutantsByStationId(stationId: "\(self.stationId)") { result in
            switch result {
            case .success(let pollutants):
                // An empty answer keeps a saved reading rather than blanking
                // it, but is still the API saying it has no current reading:
                // the page says so, and the saved one shows its own age.
                if let pollutant = pollutants.first {
                    self.pollutant = pollutant
                    self.isShowingLastGood = false
                    self.isNotReporting = false
                    self.findCam(name: pollutant.nameLocal, lat: pollutant.lat, lon: pollutant.lon)
                    self.findForecast(areaLocal: pollutant.areaLocal, countyLocal: pollutant.countyLocal, title: pollutant.displayArea)
                } else {
                    self.isNotReporting = true
                    // Online, so whatever is on screen is not an offline fallback.
                    self.isShowingLastGood = false
                }
                self.requestFinished(failed: false, generation: generation)
            case .failure(let error):
                print(error.localizedDescription)
                // Whatever is on screen — the saved reading, or one from
                // earlier this visit — is now the last good one.
                self.isShowingLastGood = self.pollutant != nil
                self.requestFinished(failed: true, generation: generation)
            }
        }
    }

    private func requestFinished(failed: Bool, generation: Int) {
        guard generation == self.generation else { return }
        answers.append(failed)
        guard answers.count == 2 else { return }
        loadFailed = answers.allSatisfy { $0 } && pollutant == nil && historicalPollutants.isEmpty
    }

    /// Read from the shared defaults rather than kept here, so the heart
    /// follows changes made in Favourites or by switching an alert on.
    var isFavourited: Bool {
        settings.savedFavouriteStations.contains(stationId)
    }

    func favouriteStationToggle() {
        if !isFavourited {
            settings.savedFavouriteStations.append(stationId)
            logFavourite(on: true)
            enableAlertsForNewFavourite()
        } else if hasAlerts {
            isConfirmingUnfavourite = true
        } else {
            removeFromFavourites()
        }
    }

    /// Takes the station out of Favourites, and turns its alerts off with it
    /// when it has any — only after `isConfirmingUnfavourite` was answered.
    /// When that isn't known yet, alerts are cleared anyway: a favourite
    /// never leaves an alert on behind it.
    func removeFromFavourites() {
        let codes = FavouriteAlerts.tagCodesToClear(
            alertsOn: alertsOn,
            knownTagCode: exactTagCode,
            candidates: candidateTagCodes
        )
        if !codes.isEmpty {
            clearAlerts(tagCodes: codes)
        }
        enablesAlertsWhenStationLoads = false
        settings.savedFavouriteStations.removeAll { $0 == stationId }
        logFavourite(on: false)
    }

    /// A new favourite gets alerts, so favouriting is the one step to being
    /// told when the air turns (FOX-31). The favourite stands whatever
    /// happens here; at the two-station cap or with notifications off the
    /// reader is told why the alerts stayed off.
    private func enableAlertsForNewFavourite() {
        guard let station = station else {
            enablesAlertsWhenStationLoads = true
            return
        }
        let stationId = stationId
        var siteId: String?
        if case .available(let cam) = cam {
            siteId = cam.siteId
        }

        FavouriteAlerts.enableForNewFavourite(
            stationId: stationId,
            tagCode: FavouriteAlerts.tagCode(countryCode: station.countryCode, name: station.name, stationId: stationId),
            siteId: siteId,
            isStillFavourite: { [weak self] in self?.isFavourited ?? false }
        ) { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .enabled:
                // Unfavourited while OneSignal was writing: don't leave an
                // alert on a station that isn't a favourite.
                if !self.isFavourited {
                    self.clearAlerts(tagCodes: self.exactTagCode.map { [$0] } ?? self.candidateTagCodes)
                }
            case .capReached:
                self.favouriteAlertsHint = .capReached
            case .notificationsDenied:
                self.favouriteAlertsHint = .notificationsDenied
            case .notChanged:
                // Also the outcome when it was unfavourited meanwhile, which
                // needs no word.
                if self.isFavourited {
                    self.favouriteAlertsHint = .notChanged
                }
            case .alreadyOn:
                break
            }
        }
    }

    /// Turns the station's alerts off as it leaves Favourites. If OneSignal
    /// can't take it now, it is tried again later, and the reader is told.
    private func clearAlerts(tagCodes: [String]) {
        FavouriteAlerts.clear(stationId: stationId, tagCodes: tagCodes) { [weak self] cleared in
            guard let self = self, !cleared, !self.isFavourited else { return }
            self.favouriteAlertsHint = .clearPending
        }
    }

    /// Where OneSignal has this station's alerts, once the station record
    /// (with its country) has loaded.
    private var exactTagCode: String? {
        station.map { FavouriteAlerts.tagCode(countryCode: $0.countryCode, name: $0.name, stationId: stationId) }
    }

    /// Where OneSignal may have them before then.
    private var candidateTagCodes: [String] {
        FavouriteAlerts.candidateTagCodes(name: pollutant?.name ?? "", stationId: stationId)
    }

    private func logFavourite(on: Bool) {
        TrackingManager.logEvent(eventName: "favourite_station_saved", parameters: [
            "label": on ? "on" : "off",
            "stationId": stationId,
        ])
    }

    /// Called by both station requests — each carries the Chinese name and
    /// coordinates the join needs. The first to find a cam wins; a miss leaves
    /// the other free to try with its copy of the name.
    ///
    /// The AQI `station_id` is never used here: it is a different numbering
    /// from MOENV's SiteId, which is what the cam URLs are keyed by.
    private func findCam(name: String, lat: Double, lon: Double) {
        if case .available = cam { return }

        StationCamStore.shared.cams { cams in
            if let cam = StationCamMatcher.match(name: name, lat: lat, lon: lon, in: cams) {
                self.cam = .available(cam)
            } else if self.cam == .loading {
                self.cam = .missing
            }
        }
    }

    /// Called by both station requests, like `findCam`; the first match wins.
    private func findForecast(areaLocal: String?, countyLocal: String?, title: String?) {
        guard forecast == nil, areaLocal != nil || countyLocal != nil else { return }

        AqiForecastStore.shared.forecasts { forecasts in
            guard self.forecast == nil else { return }
            self.forecast = AqiForecastMatcher.forecast(
                areaLocal: areaLocal,
                countyLocal: countyLocal,
                in: forecasts,
                title: title
            )
        }
    }

    /// The newest history point is from the last day, so the 24-hour chart is
    /// still about today. A station that stopped reporting long ago still
    /// returns its last 24 points, which would read as a current trend.
    var hasRecentHistory: Bool {
        guard
            let publishTime = historicalPollutants.last?.publishTime,
            let date = Date.fromApi(publishTime)
        else { return false }
        return Date().timeIntervalSince(date) < 24 * 60 * 60
    }

    /// Most recent reading, preferring live current conditions over history.
    var latestPublishTime: String? {
        pollutant?.publishTime ?? historicalPollutants.last?.publishTime
    }
}

/// What favouriting or unfavouriting just now did not do to the station's
/// alerts, as told to the reader.
enum FavouriteAlertsHint: Equatable {
    /// Favourited; two other stations already have alerts on.
    case capReached
    /// Favourited; notifications are turned off for the app in Settings.
    case notificationsDenied
    /// Favourited; OneSignal couldn't be reached, so alerts stay off.
    case notChanged
    /// Unfavourited; OneSignal couldn't be reached, so its alerts are turned
    /// off later.
    case clearPending

    /// Whether this follows favouriting rather than unfavouriting.
    var isAfterFavouriting: Bool { self != .clearPending }
}
