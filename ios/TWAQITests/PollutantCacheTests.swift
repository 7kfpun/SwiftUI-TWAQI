//
//  PollutantCacheTests.swift
//  TWAQITests
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class PollutantCacheTests: XCTestCase {
    private var directory: URL!
    /// The cache's clock. Starts at the real time, since the country file's
    /// age is its modification date on disk.
    private var now = Date()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PollutantCacheTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeCache() -> PollutantCache {
        PollutantCache(directory: directory, now: { [unowned self] in self.now })
    }

    /// The shape `current-pollutants` returns, trimmed to what the decoder needs.
    private func response(_ stations: [(id: Int, aqi: Double)]) -> Data {
        let rows = stations.map { station in
            """
            {
              "station_id": \(station.id), "code": "S\(station.id)", "lat": 25.1, "lon": 121.7,
              "aqi": \(station.aqi), "pm25": 10, "pm10": 20, "no2": 1, "so2": 1, "co": 0.1, "o3": 30,
              "wind_direction": 90, "wind_speed": 2, "publish_time": "2026-10-31T10:00:00",
              "name": { "en": "Keelung", "zh": "基隆" },
              "address": {}, "area": { "en": "North", "zh": "北部" }, "additional_info": {}
            }
            """
        }
        return Data(#"{ "success": true, "data": [\#(rows.joined(separator: ","))] }"#.utf8)
    }

    func testCountryResponseReadsBack() {
        let cache = makeCache()
        cache.save(countryCode: "twn", response: response([(91, 42), (12, 80)]))

        XCTAssertEqual(cache.pollutants(countryCode: "twn")?.map(\.stationId), [91, 12])
        XCTAssertNil(cache.pollutants(countryCode: "tha"))
    }

    /// A station the map has shown can be opened offline.
    func testCountryResponseAlsoFillsStations() {
        let cache = makeCache()
        cache.save(countryCode: "twn", response: response([(91, 42), (12, 80)]))

        XCTAssertEqual(cache.pollutant(stationId: 12)?.aqi, 80)
    }

    func testStationsComeBackInTheOrderAsked() {
        let cache = makeCache()
        cache.saveStations(response: response([(1, 10), (2, 20), (3, 30)]))

        XCTAssertEqual(cache.pollutants(stationIds: [3, 99, 1]).map(\.stationId), [3, 1])
    }

    func testNewerReadingReplacesOlderAndOthersAreKept() {
        let cache = makeCache()
        cache.saveStations(response: response([(1, 10), (2, 20)]))
        cache.saveStations(response: response([(1, 15)]))

        XCTAssertEqual(cache.pollutants(stationIds: [1, 2]).map(\.aqi), [15, 20])
    }

    func testSurvivesARelaunch() {
        let first = makeCache()
        first.saveStations(response: response([(91, 42)]))
        _ = first.pollutant(stationId: 91) // waits for the write

        XCTAssertEqual(makeCache().pollutant(stationId: 91)?.aqi, 42)
    }

    func testStationsOlderThanAWeekAreNotReturned() {
        let cache = makeCache()
        cache.saveStations(response: response([(91, 42)]))
        XCTAssertNotNil(cache.pollutant(stationId: 91)) // also waits for the write

        now += OfflineCacheRetention.maxAge + 60
        XCTAssertNil(cache.pollutant(stationId: 91))
        XCTAssertNil(makeCache().pollutant(stationId: 91))
    }

    func testCountryFileOlderThanAWeekIsNotReturned() throws {
        let cache = makeCache()
        cache.save(countryCode: "twn", response: response([(91, 42)]))
        _ = cache.pollutants(countryCode: "twn") // waits for the write

        let file = directory.appendingPathComponent(PollutantCache.countryFileName("twn"))
        let old = now.addingTimeInterval(-(OfflineCacheRetention.maxAge + 60))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)

        XCTAssertNil(cache.pollutants(countryCode: "twn"))
    }

    func testUndecodableResponseIsIgnored() {
        let cache = makeCache()
        cache.saveStations(response: response([(91, 42)]))
        cache.saveStations(response: Data("<html>gateway timeout</html>".utf8))

        XCTAssertEqual(cache.pollutant(stationId: 91)?.aqi, 42)
    }

    func testRetentionTreatsAMissingDateAsExpired() {
        XCTAssertTrue(OfflineCacheRetention.isExpired(nil))
        XCTAssertFalse(OfflineCacheRetention.isExpired(now, now: now))
        XCTAssertTrue(OfflineCacheRetention.isExpired(now - OfflineCacheRetention.maxAge - 1, now: now))
    }
}
