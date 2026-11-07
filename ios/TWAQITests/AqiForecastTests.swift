//
//  AqiForecastTests.swift
//  TWAQITests
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class AqiForecastTests: XCTestCase {

    /// Directus `items/twaqi_aqi_forecast`, as the Worker writes it from AQF_P_01.
    private let response = """
    {
      "data": [
        { "area": "北部", "forecast_date": "2026-10-31", "aqi": 62, "major_pollutant": "臭氧8小時", "minor_pollutant": "細懸浮微粒", "minor_pollutant_aqi": 55, "content": "今日北部普通。", "publish_time": "2026-10-31 10:30:00" },
        { "area": "北部", "forecast_date": "2026-11-01", "aqi": 88, "major_pollutant": "細懸浮微粒", "minor_pollutant": null, "minor_pollutant_aqi": null, "content": "明日北部普通。", "publish_time": "2026-10-31 16:30:00" },
        { "area": "北部", "forecast_date": "2026-11-02", "aqi": 45, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": "明日北部普通。", "publish_time": "2026-10-31 16:30:00" },
        { "area": "北部", "forecast_date": "2026-11-03", "aqi": 40, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-31 16:30:00" },
        { "area": "北部", "forecast_date": "2026-10-30", "aqi": 99, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-29 16:30:00" },
        { "area": "雲嘉南", "forecast_date": "2026-11-01", "aqi": 120, "major_pollutant": "細懸浮微粒", "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-31 16:30:00" },
        { "area": "馬祖", "forecast_date": "2026-11-01", "aqi": 30, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-31 16:30:00" }
      ]
    }
    """

    private func decode() throws -> [AqiForecast] {
        try JSONDecoder().decode(AqiForecastResponse.self, from: Data(response.utf8)).data
    }

    func testDecodesDirectusRows() throws {
        let rows = try decode()
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[0].area, "北部")
        XCTAssertEqual(rows[0].aqi, 62)
        XCTAssertEqual(rows[0].minorPollutantAqi, 55)
        XCTAssertNil(rows[2].majorPollutant)
        XCTAssertEqual(rows[0].status, .moderate)
        XCTAssertEqual(rows[5].status, .unhealthyforsensitivegroup)
    }

    func testDecodesPretranslatedContent() throws {
        let json = """
        { "data": [
          { "area": "北部", "forecast_date": "2026-11-03", "aqi": 62, "content": "今日北部普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": { "zh-Hant": "今日北部普通。", "en": "Northern: Moderate today." } },
          { "area": "竹苗", "forecast_date": "2026-11-03", "aqi": 70, "content": "明日竹苗普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": { "zh-Hant": "今日北部普通。", "en": "Northern: Moderate today." } },
          { "area": "中部", "forecast_date": "2026-11-03", "aqi": 80, "content": "今日中部普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": null },
          { "area": "高屏", "forecast_date": "2026-11-03", "aqi": 90, "content": "今日高屏普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": { "en": 3 } },
          { "area": "宜蘭", "forecast_date": "2026-11-03", "aqi": 30, "content": "今日宜蘭良好。", "publish_time": "2026-11-03 16:30:00" }
        ] }
        """
        let rows = try JSONDecoder().decode(AqiForecastResponse.self, from: Data(json.utf8)).data
        XCTAssertEqual(rows.count, 5)

        // Made from this row's text: used for English, not for other languages.
        XCTAssertEqual(rows[0].contentI18n?["en"], "Northern: Moderate today.")
        XCTAssertEqual(rows[0].translatedContent("en"), "Northern: Moderate today.")
        XCTAssertNil(rows[0].translatedContent("ja"))
        XCTAssertNil(rows[0].translatedContent(nil))
        // Made from older text: stale, so the original (and on-device) is used.
        XCTAssertNil(rows[1].translatedContent("en"))
        // Null, malformed or missing (older Worker, field not added yet): row still decodes.
        XCTAssertNil(rows[2].contentI18n)
        XCTAssertNil(rows[3].contentI18n)
        XCTAssertEqual(rows[3].aqi, 90)
        XCTAssertNil(rows[4].contentI18n)
        XCTAssertNil(rows[4].translatedContent("en"))

        // The area's text and its translation come from the same row.
        let area = AreaForecast(areaTitle: "North", days: [rows[0]])
        XCTAssertEqual(area.content, "今日北部普通。")
        XCTAssertEqual(area.translatedContent("en"), "Northern: Moderate today.")
        XCTAssertNil(AreaForecast(areaTitle: "Central", days: [rows[2]]).translatedContent("en"))

        // Round-trips through the offline cache file.
        let cached = try JSONDecoder().decode(AqiForecast.self, from: JSONEncoder().encode(rows[0]))
        XCTAssertEqual(cached, rows[0])
    }

    func testMatchesStationAreaToForecastArea() {
        let areas = ["北部", "竹苗", "中部", "雲嘉南", "高屏", "宜蘭", "花東", "馬祖", "金門", "澎湖"]
        XCTAssertEqual(AqiForecastMatcher.area(areaLocal: "北部空品區", countyLocal: "臺北市", in: areas), "北部")
        XCTAssertEqual(AqiForecastMatcher.area(areaLocal: "雲嘉南空品區", countyLocal: nil, in: areas), "雲嘉南")
        XCTAssertEqual(AqiForecastMatcher.area(areaLocal: " 高屏空品區 ", countyLocal: nil, in: areas), "高屏")
        // Islands may carry a catch-all area; their county decides.
        XCTAssertEqual(AqiForecastMatcher.area(areaLocal: "其他", countyLocal: "連江縣", in: areas), "馬祖")
        XCTAssertEqual(AqiForecastMatcher.area(areaLocal: nil, countyLocal: "澎湖縣", in: areas), "澎湖")
        XCTAssertNil(AqiForecastMatcher.area(areaLocal: "其他", countyLocal: "臺北市", in: areas))
        XCTAssertNil(AqiForecastMatcher.area(areaLocal: nil, countyLocal: nil, in: areas))
    }

    func testForecastForStationIsTodayOnwardsSoonestFirst() throws {
        let forecast = try XCTUnwrap(AqiForecastMatcher.forecast(
            areaLocal: "北部空品區",
            countyLocal: "臺北市",
            in: decode(),
            today: "2026-10-31"
        ))
        XCTAssertEqual(forecast.areaTitle, "北部空品區")
        // Yesterday dropped, capped at three days.
        XCTAssertEqual(forecast.days.map(\.forecastDate), ["2026-10-31", "2026-11-01", "2026-11-02"])
        // The newest publish's text is the one shown.
        XCTAssertEqual(forecast.content, "明日北部普通。")
        // English UI passes the station's English area name.
        let english = try XCTUnwrap(AqiForecastMatcher.forecast(
            areaLocal: "北部空品區", countyLocal: nil, in: decode(), title: "North", today: "2026-10-31"
        ))
        XCTAssertEqual(english.areaTitle, "North")
    }

    func testNoForecastWhenNothingCurrent() throws {
        XCTAssertNil(AqiForecastMatcher.forecast(areaLocal: "北部空品區", countyLocal: nil, in: try decode(), today: "2026-11-10"))
        XCTAssertNil(AqiForecastMatcher.forecast(areaLocal: "北部空品區", countyLocal: nil, in: [], today: "2026-10-31"))
        XCTAssertNil(AqiForecastMatcher.forecast(areaLocal: "中部空品區", countyLocal: nil, in: try decode(), today: "2026-10-31"))
    }

    func testDatesAreTaiwanDays() throws {
        // 2026-10-31 17:00 UTC is already 1 November in Taiwan.
        let late = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-31T17:00:00Z"))
        XCTAssertEqual(AqiForecastDates.today(now: late), "2026-11-01")
        XCTAssertEqual(AqiForecastDates.daysFromToday("2026-11-02", now: late), 1)

        let published = try XCTUnwrap(AqiForecastDates.parsePublishTime("2026-10-31 16:30:00"))
        XCTAssertEqual(published, ISO8601DateFormatter().date(from: "2026-10-31T08:30:00Z"))
        XCTAssertEqual(AqiForecastDates.parsePublishTime("2026-10-31T16:30"), published)
    }

    func testPollutantDisplay() {
        XCTAssertEqual(AqiForecastPollutant.display("細懸浮微粒", chinese: false), "PM2.5")
        XCTAssertEqual(AqiForecastPollutant.display("懸浮微粒", chinese: false), "PM10")
        XCTAssertEqual(AqiForecastPollutant.display("臭氧8小時", chinese: false), "O₃ (8h)")
        XCTAssertEqual(AqiForecastPollutant.display("臭氧八小時", chinese: false), "O₃ (8h)")
        XCTAssertEqual(AqiForecastPollutant.display("臭氧8小時", chinese: true), "臭氧8小時")
        XCTAssertNil(AqiForecastPollutant.display(" ", chinese: true))
    }

    func testForecastTextTranslationFallsBackToOriginal() {
        XCTAssertTrue(OnDeviceTranslation.needsTranslation("今日北部普通。"))
        XCTAssertFalse(OnDeviceTranslation.needsTranslation("smoke test FOX-8"))

        let text = "明日北部普通。\(UUID().uuidString)"
        // Nothing translated yet: the original, whatever the language.
        XCTAssertEqual(OnDeviceTranslation.display(text), text)
        // English-only text is never swapped for a translation.
        XCTAssertEqual(OnDeviceTranslation.display("smoke test"), "smoke test")

        OnDeviceTranslation.store("Tomorrow: north moderate.", for: text, target: "en")
        XCTAssertEqual(OnDeviceTranslation.cached(text, target: "en"), "Tomorrow: north moderate.")
        XCTAssertNil(OnDeviceTranslation.cached(text, target: "ja_JP"))
    }

    func testRequestReadsTodayOnwardsWithBearerToken() throws {
        let request = try XCTUnwrap(AqiForecastStore.makeRequest(
            baseURL: "https://directus.example.com",
            token: "abc",
            today: "2026-10-31"
        ))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/items/twaqi_aqi_forecast")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["filter[forecast_date][_gte]"], "2026-10-31")
        XCTAssertEqual(query["filter[archived][_neq]"], "true")
        // `*`, not a field list: naming content_i18n before Directus has it (or
        // before this token may read it) would fail the whole request.
        XCTAssertEqual(query["fields"], "*")

        XCTAssertNil(AqiForecastStore.makeRequest(baseURL: "https://directus.example.com", token: "", today: "2026-10-31"))
        XCTAssertNil(AqiForecastStore.makeRequest(baseURL: nil, token: "abc", today: "2026-10-31"))
    }
}
