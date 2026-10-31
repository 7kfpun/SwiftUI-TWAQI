//
//  FavouriteListViewModel.swift
//  TWAQI
//
//  Created by kf on 4/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class FavouriteListViewModel: ObservableObject {
    let settings = SettingsStore()

    @Published var favouritePollutants: Pollutants = []

    /// The list is the last good readings saved, because the latest request
    /// failed. Each row still shows its own reading's time.
    @Published var isShowingLastGood = false

    /// The latest request failed and there was nothing saved to show either.
    @Published var loadFailed = false

    /// Favourites with an alert on. From OneSignal once read, this device's
    /// last record of what it sent until then (or when it can't be read).
    @Published private(set) var alertedStationIds: Set<Int> = []

    /// The tag prefix OneSignal has each alerted station under, once read.
    private var alertTagCodes: [Int: String] = [:]

    private var alertsObserver: NSObjectProtocol?

    init() {
        alertsObserver = NotificationCenter.default.addObserver(
            forName: FavouriteAlerts.changed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let stationId = notification.userInfo?[FavouriteAlerts.stationIdKey] as? Int,
                  let isOn = FavouriteAlerts.isOn(in: notification, stationId: stationId)
            else { return }
            self.setAlerts(stationId: stationId, isOn: isOn)
        }
    }

    deinit {
        alertsObserver.map(NotificationCenter.default.removeObserver)
    }

    private(set) lazy var getData: () -> Void = {
        let ids = self.settings.savedFavouriteStations
        print("getFavouritePollutants", ids)

        guard !ids.isEmpty else {
            self.favouritePollutants = []
            self.isShowingLastGood = false
            self.loadFailed = false
            self.alertedStationIds = []
            return
        }

        self.alertedStationIds = Set(ids.filter { FavouriteAlerts.locallyKnown(stationId: $0) == true })

        // Show the last saved readings at once, like the station list, so
        // saved favourites never look like no favourites while the request
        // is on the wire (or failing).
        self.showSaved(ids: ids)
        self.loadFailed = false

        APIManager.getCurrentPollutantsByStationId(stationId: ids.map(String.init).joined(separator: ",")) { result in
            switch result {
            case .success(let result):
                print("getCurrentPollutantsByStationId Total: \(result.count)")
                // The API returns stations by ID; list them in the
                // reader's order, the one the widget follows too.
                let order = self.settings.savedFavouriteStations
                self.favouritePollutants = result.sorted {
                    (order.firstIndex(of: $0.stationId) ?? .max) < (order.firstIndex(of: $1.stationId) ?? .max)
                }
                self.isShowingLastGood = false
                self.loadFailed = false
                WidgetBridge.cacheFavourites(from: result)
            case .failure(let error):
                print(error.localizedDescription)
                self.showSaved(ids: self.settings.savedFavouriteStations)
                self.isShowingLastGood = !self.favouritePollutants.isEmpty
                self.loadFailed = self.favouritePollutants.isEmpty
            }
            self.readAlerts()
        }
    }

    /// Asks OneSignal which favourites have an alert on. A row's country
    /// isn't in the reading, so each is looked up under both prefixes the
    /// station screen may have used.
    private func readAlerts() {
        let stations = favouritePollutants.map {
            (id: $0.stationId, tagCodes: FavouriteAlerts.candidateTagCodes(name: $0.name, stationId: $0.stationId))
        }
        guard !stations.isEmpty else { return }
        FavouriteAlerts.fetch(stations: stations) { [weak self] alerted in
            guard let self = self, let alerted = alerted else { return }
            self.alertTagCodes = alerted
            let listed = Set(stations.map(\.id))
            // Stations not listed keep what the device last recorded.
            self.alertedStationIds = self.alertedStationIds.subtracting(listed).union(alerted.keys)
        }
    }

    private func setAlerts(stationId: Int, isOn: Bool) {
        if isOn {
            alertedStationIds.insert(stationId)
        } else {
            alertedStationIds.remove(stationId)
            alertTagCodes[stationId] = nil
        }
    }

    // MARK: - Removing

    /// Any of these has an alert on, so removing them waits on the reader.
    func needsConfirmation(toRemove ids: [Int]) -> Bool {
        !alertedStationIds.isDisjoint(with: ids)
    }

    /// Takes the stations out of Favourites, turning off the alerts of any
    /// that have them. Asked first, through `needsConfirmation`.
    func remove(stationIds ids: [Int]) {
        for id in ids where alertedStationIds.contains(id) {
            // Not read from OneSignal yet: both prefixes, by the name on
            // screen or saved with the last reading.
            let name = (favouritePollutants.first { $0.stationId == id }
                ?? PollutantCache.shared.pollutant(stationId: id))?.name ?? ""
            let codes = alertTagCodes[id].map { [$0] }
                ?? FavouriteAlerts.candidateTagCodes(name: name, stationId: id)
            FavouriteAlerts.clear(stationId: id, tagCodes: codes)
        }
        settings.savedFavouriteStations.removeAll { ids.contains($0) }
        favouritePollutants.removeAll { ids.contains($0.stationId) }
    }

    /// The saved favourites, in the reader's order, each from the list on
    /// screen or else from the last good readings on disk. Favourites with
    /// neither are left out until a request succeeds.
    private func showSaved(ids: [Int]) {
        let saved = Dictionary(
            PollutantCache.shared.pollutants(stationIds: ids).map { ($0.stationId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let shown = Dictionary(favouritePollutants.map { ($0.stationId, $0) }, uniquingKeysWith: { first, _ in first })
        let list = ids.compactMap { shown[$0] ?? saved[$0] }
        if list != favouritePollutants {
            favouritePollutants = list
        }
    }
}
