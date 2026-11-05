//
//  StationDetailLoader.swift
//  TWAQIWidget
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Fetches the extra-large widget's station detail (FOX-72): the last 24
/// hours, the 空品區 forecast and the cam. Only extra large calls this; the
/// other families fetch what they did before.
///
/// Each source is optional. A failed one keeps its last good copy from
/// `WidgetStationDetailCache`, or drops its section; none of them can blank
/// the widget.
enum StationDetailLoader {
    /// Longest side of the saved cam frame, in pixels. MOENV frames are
    /// 1920×1080; the widget draws a third of an iPad's width at most, and an
    /// extension has about 30 MB.
    static let framePixelSize = 720

    /// The saved detail and cam frame, without the network: snapshots, and
    /// the fallback when there is no station to refresh.
    static func cached(stationId: Int) -> (detail: WidgetStationDetail?, frame: UIImage?) {
        guard let cache = WidgetStationDetailCache.shared,
              let detail = cache.detail(stationId: stationId)
        else { return (nil, nil) }
        return (detail, detail.cam == nil ? nil : frame(stationId: stationId, in: cache))
    }

    /// Refreshes every source at once and saves the result.
    ///
    /// - Parameter place: the station as this refresh fetched it; nil when
    ///   that failed, and the cached place is used.
    static func refresh(stationId: Int, place: WidgetStationDetail.Place?) async -> (detail: WidgetStationDetail, frame: UIImage?) {
        let cache = WidgetStationDetailCache.shared
        let previous = cache?.detail(stationId: stationId)
        let today = AqiForecastDates.today()

        async let history = try? WatchAPI.history(stationId: stationId, limit: 24)
        async let forecasts = fetchForecasts(today: today)
        async let cams = fetchCams()

        var detail = await WidgetStationDetail.merged(
            previous: previous, stationId: stationId, place: place,
            history: history, forecasts: forecasts, cams: cams, today: today
        )

        let hasSavedFrame = cache?.hasFrame(stationId: stationId) ?? false
        switch WidgetStationDetail.camFrameAction(previous: previous?.cam, current: detail.cam, hasSavedFrame: hasSavedFrame) {
        case .remove:
            cache?.removeFrame(stationId: stationId)
        case .keep:
            break
        case .fetch:
            if let cam = detail.cam {
                let (jpeg, status) = await fetchFrame(cam)
                if let jpeg = jpeg {
                    cache?.saveFrame(jpeg, stationId: stationId)
                }
                detail.cam = WidgetStationDetail.camAfterDownload(
                    previous: previous?.cam, current: cam, status: jpeg == nil && status == 200 ? nil : status,
                    hasSavedFrame: hasSavedFrame
                )
                if detail.cam == nil {
                    detail.camFetchedAt = nil
                    cache?.removeFrame(stationId: stationId)
                } else if detail.cam != cam {
                    // The saved frame stands in: it is as old as it was.
                    detail.camFetchedAt = previous?.camFetchedAt
                }
            }
        }

        cache?.save(detail)
        let savedFrame = detail.cam == nil ? nil : cache.flatMap { Self.frame(stationId: stationId, in: $0) }
        return (detail, savedFrame)
    }

    // MARK: - Sources

    /// Every area's rows from today on, by the app's read of
    /// `twaqi_aqi_forecast`; nil when it fails or isn't configured.
    private static func fetchForecasts(today: String) async -> [AqiForecast]? {
        guard let request = AqiForecastRequest.make(
            baseURL: getEnv("DirectusUrl"), token: getEnv("DirectusFeedbackToken"), today: today
        ) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { return nil }
        return (try? JSONDecoder().decode(AqiForecastResponse.self, from: data))?.data
    }

    private static func fetchCams() async -> [StationCam]? {
        guard let (data, response) = try? await URLSession.shared.data(
            for: URLRequest(url: StationCamManifest.url, timeoutInterval: 20)
        ), let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { return nil }
        return (try? JSONDecoder().decode(StationCamManifest.self, from: data))?.cams
    }

    /// The latest frame, `stations/{siteId}.jpg`, downsampled to a JPEG of
    /// at most `framePixelSize`. The status is nil when the request failed
    /// outright; the JPEG is nil unless the status is 200 and it decoded.
    private static func fetchFrame(_ cam: WidgetStationDetail.Cam) async -> (jpeg: Data?, status: Int?) {
        let url = StationCam(siteId: cam.siteId, name: "", lat: 0, lon: 0, time: cam.time).imageURL
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20)) else {
            return (nil, nil)
        }
        let status = (response as? HTTPURLResponse)?.statusCode
        return (status == 200 ? downsample(data) : nil, status)
    }

    /// Decodes straight to a thumbnail, so the full 1920×1080 frame is never
    /// held in memory.
    static func downsample(_ data: Data, maxPixelSize: Int = framePixelSize) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func frame(stationId: Int, in cache: WidgetStationDetailCache) -> UIImage? {
        UIImage(contentsOfFile: cache.frameFile(stationId: stationId).path)
    }
}
