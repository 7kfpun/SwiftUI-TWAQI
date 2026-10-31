//
//  StationCamHistoryCache.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import ImageIO
import UIKit

/// Hourly cam frames for the station screen's 24-hour scrubber, on disk.
///
/// Sits beside `StationCamFrameCache` (the latest frame of each cam) and
/// leaves it alone: one file per (cam, hour) in Application Support/
/// `station-cams/history/`, named by `StationCamHour.cacheFileName`. An hour's
/// frame never changes once the Worker files it, so a saved one is shown as is
/// and never fetched again. Files older than `OfflineCacheRetention.maxAge`
/// are not returned, and are deleted by `OfflineCacheRetention.purge`.
///
/// Nothing here prefetches: the loader asks for one hour at a time.
final class StationCamHistoryCache {
    static let shared = StationCamHistoryCache()

    /// Subdirectory of `StationCamFrameCache.directoryName`.
    static let directoryName = "history"

    /// Longest edge of a scrubbing thumbnail, in pixels: sharp enough for the
    /// frame while the finger moves, a fraction of the 1920×1080 decode.
    static let thumbnailPixelSize = 640

    enum Result {
        /// The hour's frame, downsampled for scrubbing.
        case thumbnail(UIImage)
        /// No frame filed for this hour (404): the cam was down, or the hour
        /// isn't in yet.
        case missing
        /// Network or server trouble; worth trying again later.
        case failed
    }

    private let directory: URL
    private let session: URLSession
    private let now: () -> Date
    /// File IO and JPEG decoding, off the main thread.
    private let queue = DispatchQueue(label: "com.kfpun.twaqi.StationCamHistoryCache", qos: .userInitiated)

    init(
        directory: URL = StationCamHistoryCache.defaultDirectory,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.session = session
        self.now = now
    }

    static var defaultDirectory: URL {
        StationCamFrameCache.defaultDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    func file(for hour: StationCamHour) -> URL {
        directory.appendingPathComponent(hour.cacheFileName)
    }

    /// The saved thumbnail for `hour`, on the main queue; nil when it isn't
    /// on disk (or is over a week old). Never touches the network.
    func savedThumbnail(_ hour: StationCamHour, completion: @escaping (UIImage?) -> Void) {
        queue.async {
            let image = self.savedFile(hour).flatMap { Self.thumbnail(of: CGImageSourceCreateWithURL($0 as CFURL, nil)) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// The saved frame for `hour` at full resolution, on the main queue.
    func savedFullImage(_ hour: StationCamHour, completion: @escaping (UIImage?) -> Void) {
        queue.async {
            let image = self.savedFile(hour)
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap(UIImage.init(data:))
                .map { $0.preparingForDisplay() ?? $0 }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// `hour`'s thumbnail from disk, or else downloaded and saved. On the main
    /// queue.
    func load(_ hour: StationCamHour, completion: @escaping (Result) -> Void) {
        savedThumbnail(hour) { saved in
            if let saved {
                completion(.thumbnail(saved))
            } else {
                self.fetch(hour, completion: completion)
            }
        }
    }

    /// Downloads `hour`'s frame and saves it. A failure leaves the disk as it
    /// was.
    func fetch(_ hour: StationCamHour, completion: @escaping (Result) -> Void) {
        let request = URLRequest(url: hour.imageURL, timeoutInterval: 20)
        session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            // R2's custom domain answers 404 for a key that isn't there.
            if status == 404 {
                DispatchQueue.main.async { completion(.missing) }
                return
            }
            guard
                let status, (200..<300).contains(status),
                let data,
                let thumbnail = Self.thumbnail(of: CGImageSourceCreateWithData(data as CFData, nil))
            else {
                DispatchQueue.main.async { completion(.failed) }
                return
            }

            self.queue.async {
                try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                try? data.write(to: self.file(for: hour), options: .atomic)
                DispatchQueue.main.async { completion(.thumbnail(thumbnail)) }
            }
        }
        .resume()
    }

    // MARK: Private

    /// On `queue`.
    private func savedFile(_ hour: StationCamHour) -> URL? {
        let file = file(for: hour)
        return OfflineCacheRetention.isExpired(OfflineCacheRetention.modificationDate(of: file), now: now()) ? nil : file
    }

    /// A downsampled decode. JPEG scales down while decoding, so this is far
    /// cheaper than the full frame. Nil for anything that isn't an image.
    static func thumbnail(of source: CGImageSource?, maxPixelSize: Int = thumbnailPixelSize) -> UIImage? {
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }
}
