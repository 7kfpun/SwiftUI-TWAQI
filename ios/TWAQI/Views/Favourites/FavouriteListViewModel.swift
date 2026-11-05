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

    /// Favourites with an alert on.
    @Published private(set) var alertedStationIds: Set<Int> = []

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

        self.alertedStationIds = FavouriteAlerts.alertedStationIds().intersection(ids)

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
        }
    }

    private func setAlerts(stationId: Int, isOn: Bool) {
        if isOn {
            alertedStationIds.insert(stationId)
        } else {
            alertedStationIds.remove(stationId)
        }
    }

    // MARK: - Removing

    /// Any of these has an alert on, so removing them waits on the reader.
    func needsConfirmation(toRemove ids: [Int]) -> Bool {
        !alertedStationIds.isDisjoint(with: ids)
    }

    /// Takes the stations out of Favourites, turning off the alerts of any
    /// that have them. Asked first, through `needsConfirmation`, for those.
    func remove(stationIds ids: [Int]) {
        for id in ids {
            FavouriteAlerts.clear(stationId: id)
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
