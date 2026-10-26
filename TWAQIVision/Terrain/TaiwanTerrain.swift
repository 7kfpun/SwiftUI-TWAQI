//
//  TaiwanTerrain.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import simd

/// Taiwan's land and elevation on a regular lon/lat grid, as baked by
/// `tools/BakeTaiwanTerrain.swift` from Natural Earth coastlines and Terrarium
/// elevation tiles.
///
/// Also owns the projection from lon/lat to the model's local metres, so the
/// mesh and the station markers can't drift apart.
struct TaiwanTerrain {
    enum LoadError: Error {
        case missingResource
        case badFormat
    }

    let columns: Int
    let rows: Int
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    /// Metres above sea level per vertex, row 0 north; `nil` is sea.
    private let heights: [Int16]
    static let sea = Int16.min

    /// Model metres per kilometre on the ground.
    let horizontalScale: Float
    /// Relief is barely visible at true scale: 3,952 m over a 400 km island.
    let verticalExaggeration: Float
    /// Coastal plain sits this far above the water so it reads as land.
    static let landLift: Float = 0.002

    private static let kmPerDegreeLat = 110.574
    private static let kmPerDegreeLonAtEquator = 111.320

    var width: Float { Float(eastKm) * horizontalScale }
    var depth: Float { Float(northKm) * horizontalScale }

    private var centerLon: Double { (minLon + maxLon) / 2 }
    private var centerLat: Double { (minLat + maxLat) / 2 }
    private var kmPerDegreeLon: Double { Self.kmPerDegreeLonAtEquator * cos(centerLat * .pi / 180) }
    private var eastKm: Double { (maxLon - minLon) * kmPerDegreeLon }
    private var northKm: Double { (maxLat - minLat) * Self.kmPerDegreeLat }

    /// - Parameter fittingDepth: model size of the north–south extent, in metres.
    init(fittingDepth: Float, verticalExaggeration: Float = 8, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "TaiwanTerrain", withExtension: "bin") else {
            throw LoadError.missingResource
        }
        let data = try Data(contentsOf: url)
        guard data.count >= 48, data.prefix(4) == Data("TWTR".utf8) else { throw LoadError.badFormat }

        func read<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
            data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
        }
        func readDouble(at offset: Int) -> Double {
            Double(bitPattern: read(UInt64.self, at: offset))
        }

        guard read(UInt32.self, at: 4) == 1 else { throw LoadError.badFormat }
        columns = Int(read(UInt32.self, at: 8))
        rows = Int(read(UInt32.self, at: 12))
        minLon = readDouble(at: 16)
        minLat = readDouble(at: 24)
        maxLon = readDouble(at: 32)
        maxLat = readDouble(at: 40)

        let count = columns * rows
        guard data.count == 48 + count * 2 else { throw LoadError.badFormat }
        heights = data.withUnsafeBytes { raw in
            (0..<count).map { Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 48 + $0 * 2, as: Int16.self)) }
        }

        let northKm = (maxLat - minLat) * Self.kmPerDegreeLat
        horizontalScale = fittingDepth / Float(northKm)
        self.verticalExaggeration = verticalExaggeration
    }

    // MARK: Grid

    func metres(column: Int, row: Int) -> Int16? {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
        let value = heights[row * columns + column]
        return value == Self.sea ? nil : value
    }

    func isLand(column: Int, row: Int) -> Bool {
        metres(column: column, row: row) != nil
    }

    /// Model-space height of a grid vertex; sea counts as the waterline.
    func surfaceY(column: Int, row: Int) -> Float {
        guard let metres = metres(column: column, row: row) else { return 0 }
        return Self.landLift + Float(metres) / 1000 * horizontalScale * verticalExaggeration
    }

    func position(column: Int, row: Int) -> SIMD3<Float> {
        let x = (Float(column) / Float(columns - 1) - 0.5) * width
        let z = (Float(row) / Float(rows - 1) - 0.5) * depth
        return SIMD3(x, surfaceY(column: column, row: row), z)
    }

    // MARK: Geography

    /// Model-space point on the surface at a coordinate: x east, z south.
    func position(lat: Double, lon: Double) -> SIMD3<Float> {
        let x = Float((lon - centerLon) * kmPerDegreeLon) * horizontalScale
        let z = Float((centerLat - lat) * Self.kmPerDegreeLat) * horizontalScale
        return SIMD3(x, surfaceY(lat: lat, lon: lon), z)
    }

    /// Bilinear over the land corners only, so a coastal station isn't pulled
    /// down into the sea by its wet neighbours.
    func surfaceY(lat: Double, lon: Double) -> Float {
        let step = (maxLon - minLon) / Double(columns - 1)
        let column = (lon - minLon) / step
        let row = (maxLat - lat) / ((maxLat - minLat) / Double(rows - 1))
        let c0 = Int(column.rounded(.down)), r0 = Int(row.rounded(.down))
        let fx = Float(column - Double(c0)), fy = Float(row - Double(r0))

        var total: Float = 0, weight: Float = 0
        for (dc, dr, w) in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)]
        where isLand(column: c0 + dc, row: r0 + dr) {
            total += surfaceY(column: c0 + dc, row: r0 + dr) * w
            weight += w
        }
        return weight > 0 ? total / weight : Self.landLift
    }
}
