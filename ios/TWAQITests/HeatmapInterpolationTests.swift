//
//  HeatmapInterpolationTests.swift
//  TWAQITests
//
//  TWAQ-22: the heatmap's estimate between stations.
//

import XCTest
@testable import Taiwan_Air

final class HeatmapInterpolationTests: XCTestCase {
    private let a = HeatmapSample(latitude: 25.0, longitude: 121.5, value: 40)
    private let b = HeatmapSample(latitude: 25.0, longitude: 121.7, value: 120)

    func testAtAStationTheValueIsItsReading() throws {
        let result = try XCTUnwrap(HeatmapInterpolation.estimate(latitude: 25.0, longitude: 121.5, samples: [a, b]))
        XCTAssertEqual(result.value, 40, accuracy: 0.001)
        XCTAssertEqual(result.coverage, 1)
    }

    func testMidpointBetweenEqualDistancesIsTheMean() throws {
        let result = try XCTUnwrap(HeatmapInterpolation.estimate(
            latitude: 25.0, longitude: 121.6, samples: [a, b], maxDistanceKm: 30
        ))
        XCTAssertEqual(result.value, 80, accuracy: 0.001)
    }

    func testCloserStationWeighsMore() throws {
        let result = try XCTUnwrap(HeatmapInterpolation.estimate(
            latitude: 25.0, longitude: 121.55, samples: [a, b], maxDistanceKm: 30
        ))
        XCTAssertLessThan(result.value, 80)
        XCTAssertGreaterThan(result.value, 40)
    }

    func testBeyondReachThereIsNoEstimate() {
        // About 55 km from the nearest station.
        XCTAssertNil(HeatmapInterpolation.estimate(latitude: 25.5, longitude: 121.5, samples: [a, b]))
    }

    func testCoverageFadesFromSolidToZero() {
        let reach = HeatmapInterpolation.maxDistanceKm
        XCTAssertEqual(HeatmapInterpolation.coverage(atDistance: 1), 1)
        XCTAssertEqual(HeatmapInterpolation.coverage(atDistance: reach), 0)
        let mid = HeatmapInterpolation.coverage(atDistance: reach * 0.8)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
    }

    func testMissingReadingsDoNotContribute() {
        let none = HeatmapSample(latitude: 25.0, longitude: 121.5, value: 0)
        let nan = HeatmapSample(latitude: 25.0, longitude: 121.5, value: .nan)
        XCTAssertTrue(HeatmapInterpolation.usable([none, nan]).isEmpty)
        let bounds = HeatmapBounds(south: 24.9, west: 121.4, north: 25.1, east: 121.6)
        let grid = HeatmapInterpolation.grid(samples: [none, nan], bounds: bounds, width: 4, height: 4)
        XCTAssertTrue(grid.allSatisfy { $0 == nil })
    }

    func testMissingStationIsIgnoredNotAveraged() throws {
        let missing = HeatmapSample(latitude: 25.0, longitude: 121.51, value: 0)
        let samples = HeatmapInterpolation.usable([a, missing])
        let result = try XCTUnwrap(HeatmapInterpolation.estimate(latitude: 25.0, longitude: 121.505, samples: samples))
        XCTAssertEqual(result.value, 40, accuracy: 0.001)
    }

    func testGridLeavesGapsOutOfReach() {
        let bounds = HeatmapBounds(south: 24.0, west: 121.0, north: 26.0, east: 122.0)
        let cells = HeatmapInterpolation.grid(samples: [a], bounds: bounds, width: 10, height: 10)
        XCTAssertEqual(cells.count, 100)
        XCTAssertNil(cells[0], "North-west corner is far from the only station")
        XCTAssertTrue(cells.contains { $0 != nil })
    }

    func testZoomOpacityFadesOutWhenZoomedIn() {
        XCTAssertEqual(HeatmapInterpolation.opacity(forZoom: 7), 0.7, accuracy: 0.001)
        XCTAssertEqual(HeatmapInterpolation.opacity(forZoom: 12), 0)
        let mid = HeatmapInterpolation.opacity(forZoom: 10)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 0.7)
    }

    func testImageHasTheGridSize() {
        let cells: [(value: Double, coverage: Double)?] = [(40, 1), nil, (120, 0.5), nil]
        let image = HeatmapInterpolation.image(cells: cells, width: 2, height: 2) { _ in 0x009866 }
        XCTAssertEqual(image?.width, 2)
        XCTAssertEqual(image?.height, 2)
    }
}
