//
//  AQIPaletteTests.swift
//  TWAQITests
//
//  TWAQ-18: colour-blind-safe AQI palette and WCAG AA text contrast.
//

import XCTest
@testable import Taiwan_Air

final class AQIPaletteTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AQIPaletteTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testEveryLevelHasAColourInEveryPalette() {
        for palette in AQIPalette.allCases {
            for status in AirStatuses.allCases {
                let color = status.getColor(palette: palette)
                XCTAssertLessThanOrEqual(color, 0xFFFFFF, "\(palette) \(status)")
                XCTAssertNotEqual(color, 0, "\(palette) \(status)")
            }
        }
    }

    func testStandardPaletteKeepsTheOfficialColours() {
        let expected: [AirStatuses: UInt32] = [
            .good: 0x009866, .moderate: 0xFEDE33, .unhealthyforsensitivegroup: 0xFE9833,
            .unhealthy: 0xCC0033, .veryunhealthy: 0x660098, .hazardous: 0x7E2200, .unknown: 0x676767,
        ]
        for (status, color) in expected {
            XCTAssertEqual(status.getColor(palette: .standard), color, "\(status)")
        }
    }

    func testLevelsAreDistinctWithinEachPalette() {
        for palette in AQIPalette.allCases {
            let colors = AirStatuses.getShowAllCases().map { $0.getColor(palette: palette) }
            XCTAssertEqual(Set(colors).count, colors.count, "\(palette)")
        }
    }

    func testColourBlindPaletteDiffersFromStandardOnEveryLevel() {
        for status in AirStatuses.getShowAllCases() {
            XCTAssertNotEqual(status.getColor(palette: .colorBlindSafe), status.getColor(palette: .standard), "\(status)")
        }
    }

    func testTextOnEveryColourMeetsWCAGAA() {
        for palette in AQIPalette.allCases {
            for status in AirStatuses.allCases {
                let ratio = AQIContrast.ratio(
                    status.getForegroundColor(palette: palette),
                    status.getColor(palette: palette)
                )
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(palette) \(status): \(ratio)")
            }
        }
    }

    /// The band colour is also drawn as text or a glyph straight on the system
    /// background (rows, widgets), so the darkest colour-blind bands must stay
    /// visible on white and on the dark background (3:1, the non-text bar).
    func testDarkestColourBlindBandsStayVisibleOnLightAndDarkBackgrounds() {
        let darkBackground: UInt32 = 0x1C1C1E
        for status in [AirStatuses.veryunhealthy, .hazardous] {
            let color = status.getColor(palette: .colorBlindSafe)
            XCTAssertGreaterThanOrEqual(AQIContrast.ratio(color, 0xFFFFFF), 3, "\(status) on white")
            XCTAssertGreaterThanOrEqual(AQIContrast.ratio(color, darkBackground), 3, "\(status) on dark")
        }
    }

    /// Levels must stay apart under protanopia and deuteranopia (Machado 2009,
    /// full severity): distance between the simulated sRGB colours, 0…441.
    func testColourBlindPaletteLevelsStayApartUnderRedGreenDeficiency() {
        let protan: [[Double]] = [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
        let deutan: [[Double]] = [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]

        func simulated(_ rgb: UInt32, _ m: [[Double]]) -> [Double] {
            let linear = [16, 8, 0].map { shift -> Double in
                let c = Double((rgb >> UInt32(shift)) & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return m.map { row in
                let v = min(1, max(0, zip(row, linear).map(*).reduce(0, +)))
                return 255 * (v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055)
            }
        }

        let colors = AirStatuses.getShowAllCases().map { $0.getColor(palette: .colorBlindSafe) }
        for m in [protan, deutan] {
            for (i, a) in colors.enumerated() {
                for b in colors[(i + 1)...] {
                    let distance = zip(simulated(a, m), simulated(b, m)).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
                    XCTAssertGreaterThanOrEqual(distance, 50, "\(String(a, radix: 16)) vs \(String(b, radix: 16))")
                }
            }
        }
    }

    func testContrastMaths() {
        XCTAssertEqual(AQIContrast.ratio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
        XCTAssertEqual(AQIContrast.ratio(0x777777, 0x777777), 1, accuracy: 0.001)
        XCTAssertEqual(AQIContrast.legibleText(on: 0xFEDE33), 0x000000)
        XCTAssertEqual(AQIContrast.legibleText(on: 0x660098), 0xFFFFFF)
    }

    func testEveryBandHasADistinctLevelAndUnknownHasNone() {
        XCTAssertEqual(AirStatuses.getShowAllCases().map(\.level), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(AirStatuses.unknown.level, 0)
    }

    func testChoiceIsStoredAndStandardRemovesIt() {
        XCTAssertEqual(AQIPalette.stored(in: defaults), .standard)
        let settings = SettingsStore(defaults: defaults)

        settings.aqiPalette = .colorBlindSafe
        XCTAssertEqual(defaults.string(forKey: AQIPalette.defaultsKey), "colorBlindSafe")
        XCTAssertEqual(SettingsStore(defaults: defaults).aqiPalette, .colorBlindSafe)

        settings.aqiPalette = .standard
        XCTAssertNil(defaults.object(forKey: AQIPalette.defaultsKey))

        defaults.set("neon", forKey: AQIPalette.defaultsKey)
        XCTAssertEqual(AQIPalette.stored(in: defaults), .standard)
    }

    func testMirrorForTheWidget() {
        XCTAssertFalse(AQIPalette.mirror(.standard, to: defaults))
        XCTAssertTrue(AQIPalette.mirror(.colorBlindSafe, to: defaults))
        XCTAssertEqual(AQIPalette.stored(in: defaults), .colorBlindSafe)
        XCTAssertFalse(AQIPalette.mirror(.colorBlindSafe, to: defaults))
        XCTAssertTrue(AQIPalette.mirror(.standard, to: defaults))
        XCTAssertNil(defaults.object(forKey: AQIPalette.defaultsKey))
    }
}
