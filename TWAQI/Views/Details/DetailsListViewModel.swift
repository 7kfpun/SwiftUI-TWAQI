//
//  DetailsListViewModel.swift
//  TWAQI
//
//  Created by kf on 3/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class DetailsListViewModel: ObservableObject {

    @Published var stations: Stations = []

    private(set) lazy var getData: () -> Void = {
        let settings = SettingsStore()
        // Scoped to the supported country: those are the only stations whose
        // detail screen and notifications work.
        let countryCode = settings.supportedCountryCode.isEmpty
            ? settings.closestCountryCode
            : settings.supportedCountryCode

        // The station list barely changes, so show the last one at once and
        // let the request only refresh it.
        if self.stations.isEmpty {
            self.stations = Self.cachedStations(countryCode: countryCode)
        }

        APIManager.getStations(countryCode: countryCode) { result in
            switch result {
            case .success(let stations):
                guard !stations.isEmpty, stations != self.stations else { return }
                self.stations = stations
                Self.cache(stations, countryCode: countryCode)
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    /// Application Support rather than Caches, like `StationCamStore`: the
    /// system purges Caches under storage pressure. A file rather than
    /// defaults, since every defaults write refreshes `SettingsStore`.
    private static func cacheFile(countryCode: String) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("stations-\(countryCode).json")
    }

    private static func cachedStations(countryCode: String) -> Stations {
        guard let data = try? Data(contentsOf: cacheFile(countryCode: countryCode)) else { return [] }
        // A file an older build wrote may no longer decode; refetch instead.
        return (try? JSONDecoder().decode(Stations.self, from: data)) ?? []
    }

    private static func cache(_ stations: Stations, countryCode: String) {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        let file = cacheFile(countryCode: countryCode)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }

}
