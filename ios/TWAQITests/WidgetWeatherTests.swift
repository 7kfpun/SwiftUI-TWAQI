//
//  WidgetWeatherTests.swift
//  TWAQITests
//
//  Created by kf on 8/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import WidgetKit
import XCTest
@testable import Taiwan_Air

/// FOX-181: the weather in the medium and large widgets.
final class WidgetWeatherTests: XCTestCase {

    private let json = """
    {
      "version": 1,
      "updatedAt": "2026-11-05T04:40:00.000Z",
      "forecast": {
        "counties": {
          "臺北市": [
            { "start": "2026-11-05T12:00:00+08:00", "end": "2026-11-05T18:00:00+08:00", "wx": 4, "text": "多雲", "pop": 10, "minT": 23, "maxT": 27 }
          ]
        }
      },
      "observations": {
        "stations": [
          { "id": "466920", "name": "臺北", "county": "臺北市", "lat": 25.03766, "lon": 121.51485, "time": "2026-11-05T12:00:00+08:00", "temp": 24.3, "humidity": 75, "rain": 0.5, "wind": 3.2 }
        ]
      }
    }
    """

    /// 12:40 Taiwan time on 5 Nov.
    private let now = ISO8601DateFormatter().date(from: "2026-11-05T04:40:00Z")!

    private func file() throws -> WeatherFile {
        try JSONDecoder().decode(WeatherFile.self, from: Data(json.utf8))
    }

    private func make(
        lat: Double? = 25.062361, lon: Double? = 121.526528, county: String? = "臺北市",
        direction: Double? = 45, speed: Double? = 2, in file: WeatherFile?, at date: Date? = nil
    ) -> WidgetWeather? {
        WidgetWeather.make(
            lat: lat, lon: lon, countyLocal: county, windDirection: direction, windSpeed: speed,
            in: file, now: date ?? now
        )
    }

    // MARK: Matching and fallback

    func testReadingAndForecastAreCombined() throws {
        let weather = try XCTUnwrap(make(in: try file()))
        XCTAssertEqual(weather.temperature, 24.3)
        XCTAssertEqual(weather.humidity, 75)
        XCTAssertEqual(weather.rain, 0.5)
        XCTAssertEqual(weather.windSpeed, 3.2)
        XCTAssertEqual(weather.windDirection, 45)
        XCTAssertEqual(weather.code, 4)
        XCTAssertEqual(weather.cwaText, "多雲")
        XCTAssertEqual(weather.chanceOfRain, 10)
        XCTAssertFalse(weather.isNight)
    }

    func testNoFileMeansNoWeather() {
        XCTAssertNil(make(in: nil))
    }

    func testStationWithoutPositionHasNoWeather() throws {
        XCTAssertNil(make(lat: nil, lon: nil, county: nil, in: try file()))
        XCTAssertNil(make(lat: 0, lon: 0, county: nil, in: try file()))
    }

    func testStationOutOfRangeHasNoWeather() throws {
        // 蘭嶼: no CWA station within 20 km, and no county of its own in the forecast.
        XCTAssertNil(make(lat: 22.03, lon: 121.55, county: "臺東縣", in: try file()))
    }

    func testStaleReadingIsDroppedButForecastStays() throws {
        let later = now.addingTimeInterval(4 * 60 * 60)   // 16:40: reading is over 3 h old, forecast period still runs
        let weather = try XCTUnwrap(make(in: try file(), at: later))
        XCTAssertNil(weather.temperature)
        XCTAssertNil(weather.humidity)
        XCTAssertEqual(weather.code, 4)
    }

    func testEverythingExpiredMeansNoWeather() throws {
        XCTAssertNil(make(in: try file(), at: now.addingTimeInterval(24 * 60 * 60)))
    }

    func testCalmAirKeepsNoDirection() throws {
        let weather = try XCTUnwrap(make(speed: 0, in: try file()))
        XCTAssertNil(weather.windDirection)
        XCTAssertNil(try XCTUnwrap(make(direction: nil, in: try file())).windDirection)
    }

    func testCountyFallsBackToTheNearestCwaStation() throws {
        let weather = try XCTUnwrap(make(county: nil, in: try file()))
        XCTAssertEqual(weather.code, 4)
    }

    // MARK: Formatting

    func testTemperatureRoundsAndFallsBackToDash() {
        XCTAssertEqual(WidgetWeather.temperatureText(24.3), "24°")
        XCTAssertEqual(WidgetWeather.temperatureText(24.5), "25°")
        XCTAssertEqual(WidgetWeather.temperatureText(-0.4), "0°")
        XCTAssertEqual(WidgetWeather.temperatureText(nil), "—")
    }

    func testPercentRainAndWindText() {
        XCTAssertEqual(WidgetWeather.percentText(74.6), "75%")
        XCTAssertEqual(WidgetWeather.percentText(nil), "—")
        XCTAssertEqual(WidgetWeather.rainText(0.5), "0.5 mm")
        XCTAssertEqual(WidgetWeather.rainText(nil), "—")
        XCTAssertEqual(WidgetWeather.windText(speed: 3.2, direction: nil), "3.2 m/s")
        XCTAssertEqual(WidgetWeather.windText(speed: 3.2, direction: 45), "NE 3.2 m/s")
        XCTAssertEqual(WidgetWeather.windText(speed: 0, direction: 45), "0.0 m/s")
        XCTAssertEqual(WidgetWeather.windText(speed: nil, direction: 45), "—")
    }

    func testSkyTextIsChineseOrTheCodesEnglish() {
        let weather = WidgetWeather(code: 8, cwaText: "多雲短暫雨")
        XCTAssertEqual(weather.skyText(chinese: true), "多雲短暫雨")
        // Never CWA's Chinese in English; an unknown code has no text.
        XCTAssertNotEqual(weather.skyText(chinese: false), "多雲短暫雨")
        XCTAssertNil(WidgetWeather(code: 99, cwaText: "多雲").skyText(chinese: false))
        XCTAssertNil(WidgetWeather(temperature: 20).skyText(chinese: true))
    }

    func testCompactLineDropsHumidityAndRain() {
        let weather = WidgetWeather(
            temperature: 24.3, humidity: 75, rain: 0.5, windSpeed: 3.2, windDirection: 45, code: 4, cwaText: "多雲"
        )
        XCTAssertEqual(weather.compactText(chinese: true), "24° · NE 3.2 m/s · 多雲")
        XCTAssertFalse(weather.compactText(chinese: true).contains("75"))
        XCTAssertFalse(weather.compactText(chinese: true).contains("mm"))
    }

    func testCompactLineWithMissingFieldsShowsDashes() {
        XCTAssertEqual(WidgetWeather(code: 4, cwaText: "多雲").compactText(chinese: true), "— · — · 多雲")
        XCTAssertEqual(WidgetWeather(temperature: 20).compactText(chinese: true), "20° · —")
    }

    func testDetailItemsAreHumidityRainWind() {
        XCTAssertEqual(
            WidgetWeather(humidity: 75, rain: 0.5, windSpeed: 3.2).detailItems, ["75%", "0.5 mm", "3.2 m/s"]
        )
        XCTAssertEqual(WidgetWeather(temperature: 20).detailItems, ["—", "—", "—"])
    }

    func testSymbolFollowsTheCodeAndNight() {
        XCTAssertEqual(WidgetWeather(code: 1).symbol, "sun.max.fill")
        XCTAssertEqual(WidgetWeather(code: 1, isNight: true).symbol, "moon.stars.fill")
        XCTAssertEqual(WidgetWeather(temperature: 20).symbol, "thermometer")
    }

    func testEmpty() {
        XCTAssertTrue(WidgetWeather().isEmpty)
        XCTAssertFalse(WidgetWeather(rain: 0).isEmpty)
    }

    // MARK: Families

    func testOnlyMediumAndLargeShowWeather() {
        XCTAssertTrue(WidgetFamilyRules.showsWeather(.systemMedium))
        XCTAssertTrue(WidgetFamilyRules.showsWeather(.systemLarge))
        XCTAssertFalse(WidgetFamilyRules.showsWeather(.systemSmall))
        XCTAssertFalse(WidgetFamilyRules.showsWeather(.systemExtraLarge))
        if #available(iOS 16.0, *) {
            for family: WidgetFamily in [.accessoryCircular, .accessoryRectangular, .accessoryInline] {
                XCTAssertFalse(WidgetFamilyRules.showsWeather(family), "\(family)")
            }
        }
    }

    // MARK: Cache

    func testCacheRoundTripsAndExpires() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WidgetWeatherCache(directory: directory)
        XCTAssertNil(cache.load())

        cache.save(Data(json.utf8))
        XCTAssertEqual(cache.load(), try file())

        // A week later it is gone.
        XCTAssertNil(cache.load(now: Date().addingTimeInterval(8 * 24 * 60 * 60)))
    }
}
