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

    private(set) lazy var getData: () -> Void = {
        let ids = self.settings.savedFavouriteStations
        print("getFavouritePollutants", ids)

        guard !ids.isEmpty else {
            self.favouritePollutants = []
            self.isShowingLastGood = false
            self.loadFailed = false
            return
        }

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
