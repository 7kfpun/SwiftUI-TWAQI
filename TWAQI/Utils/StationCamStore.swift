//
//  StationCamStore.swift
//  TWAQI
//
//  Created by kf on 30/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Fetches and caches the cam manifest.
///
/// The last good manifest is kept on disk, so a station screen opened offline
/// still knows which cam it has. A cache younger than `ttl` is used as is;
/// an older one is refreshed, and kept if the refresh fails.
final class StationCamStore {
    static let shared = StationCamStore()

    static let manifestURL = StationCam.baseURL.appendingPathComponent("manifest.json")

    /// Cams are re-synced about hourly, and each frame's URL is versioned by
    /// the capture time in the manifest — so this is also how stale a frame
    /// can be.
    static let ttl: TimeInterval = 60 * 60

    private let session: URLSession
    private let cacheFile: URL

    private var cams: [StationCam]?
    private var fetchedAt: Date?
    /// Callers waiting on the request in flight, so a screen opened twice
    /// fetches once.
    private var waiting: [([StationCam]) -> Void] = []

    init(session: URLSession = .shared, cacheFile: URL = StationCamStore.defaultCacheFile) {
        self.session = session
        self.cacheFile = cacheFile
    }

    /// Application Support rather than Caches: the system purges Caches under
    /// storage pressure, and this file is what keeps cams working offline.
    static var defaultCacheFile: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("station-cams-manifest.json")
    }

    /// All known cams, on the main queue. Empty if there has never been a
    /// manifest to read.
    func cams(completion: @escaping ([StationCam]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))

        if cams == nil {
            loadFromDisk()
        }

        if let cams = cams, let fetchedAt = fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.ttl {
            completion(cams)
            return
        }

        waiting.append(completion)
        guard waiting.count == 1 else { return }

        session.dataTask(with: Self.manifestURL) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let manifest = ok ? data.flatMap { try? JSONDecoder().decode(StationCamManifest.self, from: $0) } : nil

            DispatchQueue.main.async {
                if let manifest = manifest, let data = data {
                    self.cams = manifest.cams
                    self.fetchedAt = Date()
                    try? FileManager.default.createDirectory(
                        at: self.cacheFile.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? data.write(to: self.cacheFile, options: .atomic)
                }

                let cams = self.cams ?? []
                let waiting = self.waiting
                self.waiting = []
                waiting.forEach { $0(cams) }
            }
        }
        .resume()
    }

    private func loadFromDisk() {
        guard
            let data = try? Data(contentsOf: cacheFile),
            let manifest = try? JSONDecoder().decode(StationCamManifest.self, from: data)
        else { return }

        cams = manifest.cams
        fetchedAt = (try? FileManager.default.attributesOfItem(atPath: cacheFile.path))?[.modificationDate] as? Date
    }
}
