//
//  StationWeatherStore.swift
//  TWAQI
//
//  Created by kf on 5/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Fetches and caches the CWA weather file (`WeatherFile`).
///
/// The last good file is kept on disk, so a station opened offline still has
/// its weather; `StationWeatherMatcher` then drops readings and periods that
/// have aged out. A cache younger than `ttl` is used as is; an older one is
/// refreshed, and kept if the refresh fails. A file older than
/// `OfflineCacheRetention.maxAge` is never read.
final class StationWeatherStore {
    static let shared = StationWeatherStore()

    /// The Worker syncs hourly; observations change every 10 minutes at CWA.
    static let ttl: TimeInterval = 30 * 60

    /// Top level of Application Support, named in
    /// `OfflineCacheRetention.isCacheFile` so the week-old purge covers it.
    static let cacheFileName = "cwa-weather.json"

    private let session: URLSession
    private let cacheFile: URL
    private let url: URL
    private let now: () -> Date

    private var file: WeatherFile?
    private var fetchedAt: Date?
    /// Callers waiting on the request in flight, so a screen opened twice
    /// fetches once.
    private var waiting: [(WeatherFile?) -> Void] = []

    init(
        session: URLSession = .shared,
        cacheFile: URL = StationWeatherStore.defaultCacheFile,
        url: URL = WeatherFile.url,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.cacheFile = cacheFile
        self.url = url
        self.now = now
    }

    /// Application Support rather than Caches, like the other offline caches:
    /// the system purges Caches under storage pressure.
    static var defaultCacheFile: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(cacheFileName)
    }

    /// The latest file, on the main queue. Nil if there has never been one to
    /// read (offline first launch) or the saved one is over a week old.
    func weather(completion: @escaping (WeatherFile?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))

        if file == nil {
            loadFromDisk()
        }

        if let file = file, let fetchedAt = fetchedAt, now().timeIntervalSince(fetchedAt) < Self.ttl {
            completion(file)
            return
        }

        waiting.append(completion)
        guard waiting.count == 1 else { return }

        // Without a timeout the card could wait the system's 60 s before
        // falling back to the saved file.
        session.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let decoded = ok ? data.flatMap { try? JSONDecoder().decode(WeatherFile.self, from: $0) } : nil

            DispatchQueue.main.async {
                // A body that doesn't decode is a failed refresh: the last
                // good file stays, and `fetchedAt` is left alone so the next
                // open asks again.
                if let decoded = decoded, let data = data {
                    self.file = decoded
                    self.fetchedAt = self.now()
                    try? FileManager.default.createDirectory(
                        at: self.cacheFile.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? data.write(to: self.cacheFile, options: .atomic)
                }

                let file = self.file
                let waiting = self.waiting
                self.waiting = []
                waiting.forEach { $0(file) }
            }
        }
        .resume()
    }

    private func loadFromDisk() {
        let modified = OfflineCacheRetention.modificationDate(of: cacheFile)
        guard
            !OfflineCacheRetention.isExpired(modified, now: now()),
            let data = try? Data(contentsOf: cacheFile),
            let decoded = try? JSONDecoder().decode(WeatherFile.self, from: data)
        else { return }

        file = decoded
        fetchedAt = modified
    }
}
