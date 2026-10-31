//
//  StationCamFrameCache.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import UIKit

/// The last good frame of each cam, on disk.
///
/// The station screen shows the saved frame at once and swaps in the new one
/// when it arrives (stale-while-revalidate), so the cam never drops back to a
/// spinner, and offline it still shows the last view from the station.
///
/// One frame per cam — the latest — in Application Support/`station-cams/`:
/// `{siteId}.jpg` and `{siteId}.json` holding its capture time. There is no
/// history of frames. Frames older than `OfflineCacheRetention.maxAge` are not
/// returned, and are deleted by `OfflineCacheRetention.purge`.
final class StationCamFrameCache {
    static let shared = StationCamFrameCache()

    static let directoryName = "station-cams"

    struct Frame {
        let image: UIImage
        /// The manifest's capture time for this frame, e.g. `"2026-10-30T22:30:00+08:00"`.
        let time: String?
    }

    private struct Meta: Codable {
        let time: String?
    }

    private let directory: URL
    private let session: URLSession
    private let now: () -> Date
    /// File IO and JPEG decoding, off the main thread.
    private let queue = DispatchQueue(label: "com.kfpun.twaqi.StationCamFrameCache", qos: .userInitiated)

    init(
        directory: URL = StationCamFrameCache.defaultDirectory,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.session = session
        self.now = now
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// The saved frame for `siteId`, on the main queue; nil when there is
    /// none younger than a week.
    func savedFrame(siteId: String, completion: @escaping (Frame?) -> Void) {
        queue.async {
            let frame = self.readFrame(siteId: siteId)
            DispatchQueue.main.async { completion(frame) }
        }
    }

    /// Downloads `cam`'s current frame and saves it over the last one. Nil, on
    /// the main queue, when the download fails or isn't an image; the saved
    /// frame is then left as it was.
    func fetch(_ cam: StationCam, completion: @escaping (Frame?) -> Void) {
        let request = URLRequest(url: cam.imageURL, timeoutInterval: 20)
        session.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            guard ok, let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            self.queue.async {
                self.write(data, time: cam.time, siteId: cam.siteId)
                let frame = Frame(image: image.preparingForDisplay() ?? image, time: cam.time)
                DispatchQueue.main.async { completion(frame) }
            }
        }
        .resume()
    }

    // MARK: Private — on `queue`

    private func imageFile(_ siteId: String) -> URL {
        directory.appendingPathComponent("\(siteId).jpg")
    }

    private func metaFile(_ siteId: String) -> URL {
        directory.appendingPathComponent("\(siteId).json")
    }

    private func readFrame(siteId: String) -> Frame? {
        let file = imageFile(siteId)
        guard
            !OfflineCacheRetention.isExpired(OfflineCacheRetention.modificationDate(of: file), now: now()),
            let data = try? Data(contentsOf: file),
            let image = UIImage(data: data)
        else { return nil }

        let meta = (try? Data(contentsOf: metaFile(siteId))).flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
        return Frame(image: image.preparingForDisplay() ?? image, time: meta?.time)
    }

    private func write(_ data: Data, time: String?, siteId: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Old meta out, frame in, new meta in. Interrupted anywhere, a frame
        // is left with no time (shown without one, and downloaded again)
        // rather than with another frame's time.
        try? FileManager.default.removeItem(at: metaFile(siteId))
        guard (try? data.write(to: imageFile(siteId), options: .atomic)) != nil else { return }
        if let meta = try? JSONEncoder().encode(Meta(time: time)) {
            try? meta.write(to: metaFile(siteId), options: .atomic)
        }
    }
}
