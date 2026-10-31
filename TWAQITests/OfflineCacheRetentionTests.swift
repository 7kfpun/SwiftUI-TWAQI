//
//  OfflineCacheRetentionTests.swift
//  TWAQITests
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class OfflineCacheRetentionTests: XCTestCase {
    private var directory: URL!
    private let now = Date()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineCacheRetentionTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory.appendingPathComponent(StationCamFrameCache.directoryName),
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    @discardableResult
    private func file(_ path: String, age: TimeInterval) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path)
    }

    private let week = OfflineCacheRetention.maxAge
    private let day: TimeInterval = 24 * 60 * 60

    func testPurgesEveryCacheOlderThanAWeek() throws {
        let old = [
            "stations-twn.json",
            "pollutants-twn.json",
            "pollutants-stations.json",
            "aqi-forecast.json",
            "station-cams-manifest.json",
            "station-cams/001.jpg",
            "station-cams/001.json",
        ]
        for path in old {
            try file(path, age: week + day)
        }

        let removed = OfflineCacheRetention.purge(directory: directory, now: now)

        XCTAssertEqual(removed.count, old.count)
        for path in old {
            XCTAssertFalse(exists(path), path)
        }
    }

    func testKeepsCachesYoungerThanAWeek() throws {
        try file("stations-twn.json", age: week - day)
        try file("aqi-forecast.json", age: 60)
        try file("station-cams/057.jpg", age: day)

        XCTAssertTrue(OfflineCacheRetention.purge(directory: directory, now: now).isEmpty)
        XCTAssertTrue(exists("stations-twn.json"))
        XCTAssertTrue(exists("aqi-forecast.json"))
        XCTAssertTrue(exists("station-cams/057.jpg"))
    }

    /// Application Support is shared with the SDKs; only our caches go.
    func testLeavesOtherFilesAlone() throws {
        try file("com.google.gmp.measurement.json", age: week * 10)
        try file("settings.json", age: week * 10)

        OfflineCacheRetention.purge(directory: directory, now: now)

        XCTAssertTrue(exists("com.google.gmp.measurement.json"))
        XCTAssertTrue(exists("settings.json"))
    }

    func testMissingDirectoryIsFine() {
        let missing = directory.appendingPathComponent("nope")
        XCTAssertTrue(OfflineCacheRetention.purge(directory: missing, now: now).isEmpty)
    }

    /// The watch and widgets can't see `OfflineCacheRetention`; they keep
    /// their own copy of the ceiling.
    func testWatchStoreUsesTheSameCeiling() {
        XCTAssertEqual(WatchStore.maxReadingAge, OfflineCacheRetention.maxAge)
    }

    func testWatchReadingAgeComesFromTaiwanPublishTime() throws {
        let decoder = JSONDecoder()
        func reading(_ publishTime: String) throws -> WatchReading {
            try decoder.decode(WatchReading.self, from: Data("""
            { "stationId": 91, "code": "KL", "name": "Keelung", "nameLocal": "基隆", "aqi": 42,
              "pm25": 9, "pm10": 21, "o3": 31, "co": 0.3, "so2": 1, "no2": 12,
              "windDirection": 90, "windSpeed": 2, "publishTime": "\(publishTime)" }
            """.utf8))
        }

        // 2026-10-31 12:00 in Taiwan is 04:00 UTC.
        let now = ISO8601DateFormatter().date(from: "2026-10-31T04:00:00Z")!
        XCTAssertFalse(WatchStore.isExpired(try reading("2026-10-25T12:00:00"), now: now))
        XCTAssertTrue(WatchStore.isExpired(try reading("2026-10-24T11:00:00"), now: now))
        // Gallery placeholders have no time; they are kept.
        XCTAssertFalse(WatchStore.isExpired(try reading(""), now: now))
    }
}

final class StationCamFrameCacheTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StationCamFrameCacheTests-\(UUID().uuidString)")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubProtocol.response = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private let cam = StationCam(siteId: "001", name: "基隆", lat: 25.1, lon: 121.7, time: "2026-10-30T22:30:00+08:00")

    private var jpeg: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
    }

    private func fetch(_ cache: StationCamFrameCache) -> StationCamFrameCache.Frame? {
        let done = expectation(description: "fetch")
        var result: StationCamFrameCache.Frame?
        cache.fetch(cam) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    private func saved(_ cache: StationCamFrameCache) -> StationCamFrameCache.Frame? {
        let done = expectation(description: "saved")
        var result: StationCamFrameCache.Frame?
        cache.savedFrame(siteId: cam.siteId) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    func testFetchedFrameIsSavedWithItsCaptureTime() {
        StubProtocol.response = (200, jpeg)
        let cache = StationCamFrameCache(directory: directory, session: session)

        XCTAssertNil(saved(cache))
        XCTAssertEqual(fetch(cache)?.time, cam.time)
        XCTAssertEqual(saved(cache)?.time, cam.time)
    }

    /// Stale-while-revalidate: a failed refresh leaves the last frame in place.
    func testFailedFetchKeepsTheSavedFrame() {
        let cache = StationCamFrameCache(directory: directory, session: session)
        StubProtocol.response = (200, jpeg)
        _ = fetch(cache)

        StubProtocol.response = (503, Data("busy".utf8))
        XCTAssertNil(fetch(cache))
        XCTAssertEqual(saved(cache)?.time, cam.time)
    }

    func testNonImageBodyIsNotSaved() {
        StubProtocol.response = (200, Data("<html>".utf8))
        let cache = StationCamFrameCache(directory: directory, session: session)

        XCTAssertNil(fetch(cache))
        XCTAssertNil(saved(cache))
    }

    func testFrameOlderThanAWeekIsNotReturned() throws {
        StubProtocol.response = (200, jpeg)
        _ = fetch(StationCamFrameCache(directory: directory, session: session))

        let later = Date().addingTimeInterval(OfflineCacheRetention.maxAge + 60)
        XCTAssertNil(saved(StationCamFrameCache(directory: directory, session: session, now: { later })))
    }
}

private final class StubProtocol: URLProtocol {
    static var response: (status: Int, body: Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let (status, body) = Self.response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
