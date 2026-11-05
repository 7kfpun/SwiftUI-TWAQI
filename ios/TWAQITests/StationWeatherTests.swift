//
//  StationWeatherTests.swift
//  TWAQITests
//
//  Created by kf on 5/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import UIKit
import XCTest
@testable import Taiwan_Air

final class StationWeatherTests: XCTestCase {

    /// `weather/latest.json` as the Worker writes it.
    private let json = """
    {
      "version": 1,
      "updatedAt": "2026-11-05T04:40:00.000Z",
      "forecast": {
        "fetchedAt": "2026-11-05T04:40:00.000Z",
        "counties": {
          "臺北市": [
            { "start": "2026-11-05T12:00:00+08:00", "end": "2026-11-05T18:00:00+08:00", "wx": 4, "text": "多雲", "pop": 10, "minT": 23, "maxT": 27 },
            { "start": "2026-11-05T18:00:00+08:00", "end": "2026-11-06T06:00:00+08:00", "wx": 8, "text": "多雲短暫雨", "pop": 30, "minT": 21, "maxT": 24 },
            { "start": "2026-11-06T06:00:00+08:00", "end": "2026-11-06T18:00:00+08:00", "wx": 11, "text": "陰短暫雨", "pop": 60, "minT": 20, "maxT": 23 },
            { "start": "2026-11-06T18:00:00+08:00", "end": "2026-11-07T06:00:00+08:00", "wx": 7, "text": "陰天", "pop": 20, "minT": 19, "maxT": 22 }
          ],
          "花蓮縣": [
            { "start": "2026-11-05T12:00:00+08:00", "end": "2026-11-05T18:00:00+08:00", "wx": 2, "text": "晴時多雲", "pop": 0, "minT": 22, "maxT": 28 },
            { "start": "2026-11-05T18:00:00+08:00", "end": "2026-11-06T06:00:00+08:00", "wx": 4, "text": "多雲", "pop": 10, "minT": 20, "maxT": 24 },
            { "start": "2026-11-06T06:00:00+08:00", "end": "2026-11-06T18:00:00+08:00", "wx": 3, "text": "多雲時晴", "pop": null, "minT": null, "maxT": 27 }
          ]
        }
      },
      "observations": {
        "fetchedAt": "2026-11-05T04:40:00.000Z",
        "stations": [
          { "id": "466920", "name": "臺北", "county": "臺北市", "lat": 25.03766, "lon": 121.51485, "time": "2026-11-05T12:00:00+08:00", "temp": 24.3, "humidity": 75, "rain": 0.5, "wind": 3.2 },
          { "id": "466990", "name": "花蓮", "county": "花蓮縣", "lat": 23.97513, "lon": 121.61328, "time": "2026-11-05T12:00:00+08:00", "temp": 26.8, "humidity": 68, "rain": 0, "wind": null },
          { "id": "466930", "name": "竹子湖", "county": "臺北市", "lat": 25.16208, "lon": 121.54455, "time": "2026-11-05T07:00:00+08:00", "temp": 19, "humidity": 95, "rain": 2, "wind": 1 }
        ]
      }
    }
    """

    /// 12:40 Taiwan time on 5 Nov.
    private let now = ISO8601DateFormatter().date(from: "2026-11-05T04:40:00Z")!

    // AQI stations (MOENV positions).
    private let zhongshan = (lat: 25.062361, lon: 121.526528)   // 中山, Taipei
    private let hualien = (lat: 23.971306, lon: 121.599769)     // 花蓮
    private let yangming = (lat: 25.182722, lon: 121.529583)    // 陽明, near 竹子湖
    private let lanyu = (lat: 22.03, lon: 121.55)               // 蘭嶼: no CWA station in the file within 20 km

    private func file() throws -> WeatherFile {
        try JSONDecoder().decode(WeatherFile.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    func testDecodesTheWorkerFile() throws {
        let file = try file()
        XCTAssertEqual(file.forecast?.counties.count, 2)
        XCTAssertEqual(file.forecast?.counties["臺北市"]?.first,
                       WeatherPeriod(start: "2026-11-05T12:00:00+08:00", end: "2026-11-05T18:00:00+08:00",
                                     wx: 4, text: "多雲", pop: 10, minT: 23, maxT: 27))
        XCTAssertNil(file.forecast?.counties["花蓮縣"]?[2].pop)
        let taipei = try XCTUnwrap(file.observations?.stations.first)
        XCTAssertEqual(taipei.name, "臺北")
        XCTAssertEqual(taipei.humidity, 75)
        XCTAssertNil(file.observations?.stations[1].wind)
        XCTAssertEqual(taipei.observedAt, ISO8601DateFormatter().date(from: "2026-11-05T04:00:00Z"))
    }

    func testDecodesSectionsThatNeverLoaded() throws {
        let file = try JSONDecoder().decode(WeatherFile.self, from: Data("""
        { "version": 1, "updatedAt": "2026-11-05T04:40:00.000Z", "forecast": null, "observations": null }
        """.utf8))
        XCTAssertNil(file.forecast)
        XCTAssertNil(file.observations)
        // Hidden state: nothing to show.
        XCTAssertNil(StationWeatherMatcher.weather(lat: zhongshan.lat, lon: zhongshan.lon, countyLocal: "臺北市", in: file, now: now))
    }

    func testPeriodTimesAreTaiwanTime() throws {
        let period = try XCTUnwrap(file().forecast?.counties["臺北市"]?[1])
        XCTAssertEqual(period.startDate, ISO8601DateFormatter().date(from: "2026-11-05T10:00:00Z"))
        XCTAssertTrue(period.isNight)
        XCTAssertFalse(try XCTUnwrap(file().forecast?.counties["臺北市"]?[0]).isNight)
        XCTAssertEqual(StationWeatherView.timeRange(period), "11/5 18:00–06:00")
        // No offset: read as Taiwan time.
        XCTAssertEqual(WeatherDates.parse("2026-11-05 18:00:00"), period.startDate)
    }

    // MARK: Nearest station

    func testTaipeiGetsTheNearestFreshStationAndItsCounty() throws {
        let weather = try XCTUnwrap(StationWeatherMatcher.weather(
            lat: zhongshan.lat, lon: zhongshan.lon, countyLocal: "臺北市", in: file(), now: now
        ))
        XCTAssertEqual(weather.now?.observation.id, "466920")
        XCTAssertEqual(weather.now?.distanceKm ?? 0, 2.9, accuracy: 0.2)
        XCTAssertEqual(weather.county, "臺北市")
        XCTAssertEqual(weather.periods.map(\.wx), [4, 8, 11])
    }

    func testHualienGetsHualien() throws {
        let weather = try XCTUnwrap(StationWeatherMatcher.weather(
            lat: hualien.lat, lon: hualien.lon, countyLocal: "花蓮縣", in: file(), now: now
        ))
        XCTAssertEqual(weather.now?.observation.name, "花蓮")
        XCTAssertEqual(weather.county, "花蓮縣")
        XCTAssertEqual(weather.periods.count, 3)
    }

    func testNoStationWithinTwentyKilometresMeansNoReading() throws {
        let stations = try XCTUnwrap(file().observations?.stations)
        XCTAssertNil(StationWeatherMatcher.nearest(lat: lanyu.lat, lon: lanyu.lon, in: stations, now: now))

        // 20 km is the edge: just inside counts, just outside doesn't.
        let taipei = stations[0]
        let degreesPerKm = 1 / 111.195
        XCTAssertNotNil(StationWeatherMatcher.nearest(lat: taipei.lat + 19.9 * degreesPerKm, lon: taipei.lon, in: [taipei], now: now))
        XCTAssertNil(StationWeatherMatcher.nearest(lat: taipei.lat + 20.1 * degreesPerKm, lon: taipei.lon, in: [taipei], now: now))
    }

    func testStationWithoutPositionHasNoReading() throws {
        let stations = try XCTUnwrap(file().observations?.stations)
        XCTAssertNil(StationWeatherMatcher.nearest(lat: 0, lon: 0, in: stations, now: now))
        // …but still gets its county's forecast.
        let weather = try XCTUnwrap(StationWeatherMatcher.weather(lat: 0, lon: 0, countyLocal: "臺北市", in: file(), now: now))
        XCTAssertNil(weather.now)
        XCTAssertEqual(weather.periods.count, 3)
    }

    // MARK: Staleness

    func testStaleReadingGivesWayToAFreshOneFurtherOff() throws {
        // 竹子湖 is closest to 陽明 but its reading is 5 h 40 min old; 臺北 is
        // ~16 km off with a fresh one.
        let stations = try XCTUnwrap(file().observations?.stations)
        let any = StationWeatherMatcher.nearest(lat: yangming.lat, lon: yangming.lon, in: stations, now: nil)
        XCTAssertEqual(any?.observation.id, "466930")
        let fresh = StationWeatherMatcher.nearest(lat: yangming.lat, lon: yangming.lon, in: stations, now: now)
        XCTAssertEqual(fresh?.observation.id, "466920")
    }

    func testReadingAgeLimits() {
        let limit = StationWeatherMatcher.maxObservationAge
        XCTAssertTrue(StationWeatherMatcher.isFresh(now.addingTimeInterval(-limit), now: now))
        XCTAssertFalse(StationWeatherMatcher.isFresh(now.addingTimeInterval(-limit - 1), now: now))
        XCTAssertTrue(StationWeatherMatcher.isFresh(now.addingTimeInterval(5 * 60), now: now))
        XCTAssertFalse(StationWeatherMatcher.isFresh(now.addingTimeInterval(60 * 60), now: now))
    }

    func testEndedPeriodsAreDropped() throws {
        let periods = try XCTUnwrap(file().forecast?.counties["臺北市"])
        // 19:00 on the 5th: the 12–18 period is over, the next three remain.
        let evening = now.addingTimeInterval(6 * 60 * 60 + 20 * 60)
        XCTAssertEqual(StationWeatherMatcher.upcoming(periods, now: evening).map(\.wx), [8, 11, 7])
        // A period ending exactly now is over.
        let sixPM = ISO8601DateFormatter().date(from: "2026-11-05T10:00:00Z")!
        XCTAssertEqual(StationWeatherMatcher.upcoming(periods, now: sixPM).first?.wx, 8)
    }

    func testAWeekOldFileShowsNothing() throws {
        // Offline for days: every reading is stale and every period has ended.
        let later = now.addingTimeInterval(3 * 24 * 60 * 60)
        XCTAssertNil(try StationWeatherMatcher.weather(lat: zhongshan.lat, lon: zhongshan.lon, countyLocal: "臺北市", in: file(), now: later))
    }

    // MARK: County

    func testCountyFallsBackToTheNearestStationsAndAccepts台() {
        let counties: Set<String> = ["臺北市", "花蓮縣"]
        let hualienStation = WeatherObservation(id: "466990", name: "花蓮", county: "花蓮縣", lat: 0, lon: 0,
                                                time: "", temp: nil, humidity: nil, rain: nil, wind: nil)
        XCTAssertEqual(StationWeatherMatcher.county(countyLocal: "台北市", nearest: nil, in: counties), "臺北市")
        XCTAssertEqual(StationWeatherMatcher.county(countyLocal: nil, nearest: hualienStation, in: counties), "花蓮縣")
        XCTAssertEqual(StationWeatherMatcher.county(countyLocal: "連江縣", nearest: hualienStation, in: counties), "花蓮縣")
        XCTAssertNil(StationWeatherMatcher.county(countyLocal: "連江縣", nearest: nil, in: counties))
    }

    func testHiddenWhenNothingIsInRangeOrInTheForecast() throws {
        XCTAssertNil(try StationWeatherMatcher.weather(lat: lanyu.lat, lon: lanyu.lon, countyLocal: "臺東縣", in: file(), now: now))
        XCTAssertNil(try StationWeatherMatcher.weather(lat: 0, lon: 0, countyLocal: nil, in: file(), now: now))
    }

    func testForecastWithoutAReadingStillShows() throws {
        // 21:40 on the 6th: the 12:00 reading on the 5th is long stale, the
        // 18:00–06:00 period is still on.
        let weather = try XCTUnwrap(StationWeatherMatcher.weather(
            lat: zhongshan.lat, lon: zhongshan.lon, countyLocal: "臺北市", in: file(),
            now: now.addingTimeInterval(33 * 60 * 60)
        ))
        XCTAssertNil(weather.now)
        XCTAssertEqual(weather.periods.map(\.wx), [7])
    }

    // MARK: Weather codes

    private func lproj(_ identifier: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: identifier, ofType: "lproj"), identifier)
        return try XCTUnwrap(Bundle(path: path), identifier)
    }

    func testEveryCodeHasEnglishAndChineseText() throws {
        XCTAssertEqual(WeatherCode.all.count, 41)
        XCTAssertFalse(WeatherCode.all.contains(40))
        let en = try lproj("en")
        let zh = try lproj("zh-Hant")
        for code in WeatherCode.all {
            let english = try XCTUnwrap(WeatherCode.text(code: code, cwaText: nil, chinese: false, bundle: en), "\(code)")
            XCTAssertFalse(english.isEmpty, "\(code)")
            XCTAssertNil(english.range(of: "\\p{Han}", options: .regularExpression), "\(code): \(english)")
            let chinese = try XCTUnwrap(WeatherCode.text(code: code, cwaText: nil, chinese: true, bundle: zh), "\(code)")
            XCTAssertNotNil(chinese.range(of: "\\p{Han}", options: .regularExpression), "\(code): \(chinese)")
        }
    }

    func testChineseShowsCWAsTextAndEnglishNeverDoes() throws {
        let en = try lproj("en")
        XCTAssertEqual(WeatherCode.text(code: 8, cwaText: "午後短暫陣雨", chinese: true, bundle: en), "午後短暫陣雨")
        XCTAssertEqual(WeatherCode.text(code: 8, cwaText: "午後短暫陣雨", chinese: false, bundle: en), "Partly cloudy, occasional showers")
        // A code this build doesn't know: no English rather than Chinese.
        XCTAssertNil(WeatherCode.text(code: 40, cwaText: "新天氣", chinese: false, bundle: en))
        XCTAssertNil(WeatherCode.text(code: nil, cwaText: "新天氣", chinese: false, bundle: en))
        XCTAssertEqual(WeatherCode.text(code: 99, cwaText: "新天氣", chinese: true, bundle: en), "新天氣")
    }

    func testEveryCodeHasAnSFSymbolOnThisOS() {
        for code in WeatherCode.all + [40, 99] {
            for night in [false, true] {
                let name = WeatherCode.symbol(code: code, night: night)
                XCTAssertNotNil(UIImage(systemName: name), "\(code) night=\(night): \(name)")
            }
        }
        XCTAssertEqual(WeatherCode.symbol(code: 1, night: false), "sun.max.fill")
        XCTAssertEqual(WeatherCode.symbol(code: 1, night: true), "moon.stars.fill")
        XCTAssertEqual(WeatherCode.symbol(code: 18, night: false), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherCode.symbol(code: 42, night: true), "snowflake")
        XCTAssertEqual(WeatherCode.symbol(code: nil, night: false), "cloud.fill")
    }

    // MARK: Formatting

    func testFormatting() {
        XCTAssertEqual(StationWeatherView.temperature(24.3), "24°")
        XCTAssertEqual(StationWeatherView.temperature(-0.4), "0°")
        XCTAssertEqual(StationWeatherView.temperature(nil), "—")
        XCTAssertEqual(StationWeatherView.temperatureRange(min: 21, max: 27.6), "21–28°")
        XCTAssertEqual(StationWeatherView.temperatureRange(min: nil, max: 27), "27°")
        XCTAssertEqual(StationWeatherView.temperatureRange(min: nil, max: nil), "—")
        XCTAssertEqual(StationWeatherView.percent(30), "30%")
        XCTAssertEqual(StationWeatherView.millimetres(0.5), "0.5 mm")
        XCTAssertEqual(StationWeatherView.windSpeed(nil), "—")
    }

    /// 02:00 Thursday (Taiwan): the 18:00–06:00 period that started Wednesday is
    /// running, so it is 今天, not Wednesday; the next one starts today too.
    func testPeriodRunningPastMidnightIsToday() throws {
        let night = WeatherPeriod(start: "2026-11-04T18:00:00+08:00", end: "2026-11-05T06:00:00+08:00",
                                  wx: 1, text: nil, pop: 0, minT: 20, maxT: 24)
        let day = WeatherPeriod(start: "2026-11-05T06:00:00+08:00", end: "2026-11-05T18:00:00+08:00",
                                wx: 1, text: nil, pop: 0, minT: 22, maxT: 27)
        let tonight = WeatherPeriod(start: "2026-11-05T18:00:00+08:00", end: "2026-11-06T06:00:00+08:00",
                                    wx: 1, text: nil, pop: 0, minT: 20, maxT: 24)
        let today = "Forecast.today".localized
        let tomorrow = "Forecast.tomorrow".localized

        let twoAM = try XCTUnwrap(WeatherDates.parse("2026-11-05T02:00:00+08:00"))
        XCTAssertEqual(StationWeatherView.dayTitle(night, now: twoAM), today)
        XCTAssertEqual(StationWeatherView.dayTitle(day, now: twoAM), today)

        // At 20:00 the period that starts tonight is today; at 06:00 the night one has ended.
        let eightPM = try XCTUnwrap(WeatherDates.parse("2026-11-05T20:00:00+08:00"))
        XCTAssertEqual(StationWeatherView.dayTitle(tonight, now: eightPM), today)
        let sixAM = try XCTUnwrap(WeatherDates.parse("2026-11-05T06:00:00+08:00"))
        XCTAssertNotEqual(StationWeatherView.dayTitle(night, now: sixAM), today)

        // The running night and tonight both read 18:00–06:00; the start date tells them apart.
        XCTAssertEqual(StationWeatherView.timeRange(night), "11/4 18:00–06:00")
        XCTAssertEqual(StationWeatherView.timeRange(tonight), "11/5 18:00–06:00")
        XCTAssertEqual(StationWeatherView.timeRange(day), "06:00–18:00")

        // A later period keeps its own day.
        let next = WeatherPeriod(start: "2026-11-06T06:00:00+08:00", end: "2026-11-06T18:00:00+08:00",
                                 wx: 1, text: nil, pop: 0, minT: 22, maxT: 27)
        XCTAssertEqual(StationWeatherView.dayTitle(next, now: twoAM), tomorrow)
    }
}

// MARK: - Store

final class StationWeatherStoreTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!
    private let body = Data("""
    { "version": 1, "updatedAt": "2026-11-05T04:40:00.000Z", "forecast": null,
      "observations": { "fetchedAt": "2026-11-05T04:40:00.000Z", "stations": [
        { "id": "466920", "name": "臺北", "county": "臺北市", "lat": 25.03766, "lon": 121.51485,
          "time": "2026-11-05T12:00:00+08:00", "temp": 24.3, "humidity": 75, "rain": 0.5, "wind": 3.2 } ] } }
    """.utf8)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("StationWeatherStoreTests-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeatherStubProtocol.self]
        session = URLSession(configuration: config)
        WeatherStubProtocol.response = nil
        WeatherStubProtocol.requests = 0
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var cacheFile: URL { directory.appendingPathComponent(StationWeatherStore.cacheFileName) }

    private func load(_ store: StationWeatherStore) -> WeatherFile? {
        let done = expectation(description: "weather")
        var result: WeatherFile?
        store.weather { file in
            result = file
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    func testFetchedFileIsSavedAndReadBackOffline() throws {
        WeatherStubProtocol.response = (200, body)
        XCTAssertEqual(load(StationWeatherStore(session: session, cacheFile: cacheFile))?.observations?.stations.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))

        // A new launch, offline: the saved file answers.
        WeatherStubProtocol.response = nil
        let offline = StationWeatherStore(session: session, cacheFile: cacheFile, now: { Date().addingTimeInterval(StationWeatherStore.ttl + 60) })
        XCTAssertEqual(load(offline)?.observations?.stations.first?.id, "466920")
    }

    func testWithinTheTTLNoSecondRequest() {
        WeatherStubProtocol.response = (200, body)
        let store = StationWeatherStore(session: session, cacheFile: cacheFile)
        _ = load(store)
        _ = load(store)
        XCTAssertEqual(WeatherStubProtocol.requests, 1)
    }

    func testBadBodyIsNotSavedAndNothingShows() {
        WeatherStubProtocol.response = (200, Data("<html>busy</html>".utf8))
        XCTAssertNil(load(StationWeatherStore(session: session, cacheFile: cacheFile)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))

        WeatherStubProtocol.response = (404, body)
        XCTAssertNil(load(StationWeatherStore(session: session, cacheFile: cacheFile)))
    }

    func testSavedFileOlderThanAWeekIsNotRead() throws {
        WeatherStubProtocol.response = (200, body)
        _ = load(StationWeatherStore(session: session, cacheFile: cacheFile))

        WeatherStubProtocol.response = nil
        let later = Date().addingTimeInterval(OfflineCacheRetention.maxAge + 60)
        XCTAssertNil(load(StationWeatherStore(session: session, cacheFile: cacheFile, now: { later })))
    }

    func testDefaultCacheFileIsOneThePurgeScans() {
        XCTAssertTrue(OfflineCacheRetention.isCacheFile(named: StationWeatherStore.defaultCacheFile.lastPathComponent))
        XCTAssertEqual(
            StationWeatherStore.defaultCacheFile.deletingLastPathComponent(),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        )
    }
}

private final class WeatherStubProtocol: URLProtocol {
    static var response: (status: Int, body: Data)?
    static var requests = 0
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let stub = Self.response
        Self.lock.unlock()
        guard let (status, body) = stub, let url = request.url else {
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
