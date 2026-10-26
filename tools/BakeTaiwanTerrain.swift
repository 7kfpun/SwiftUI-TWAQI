//
//  BakeTaiwanTerrain.swift
//  tools
//
//  Bakes the heightmap the visionOS app builds its 3D Taiwan from.
//
//  Inputs (download into an empty scratch directory):
//    - Natural Earth 10m admin-0 countries (public domain), for the coastline:
//      https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson
//    - Terrarium elevation tiles at zoom 9 (Mapzen / AWS Terrain Tiles), as
//      `tiles/9_<x>_<y>.png`, covering the bounding box below:
//      https://s3.amazonaws.com/elevation-tiles-prod/terrarium/9/<x>/<y>.png
//
//  Usage:
//    swiftc -O tools/BakeTaiwanTerrain.swift -o /tmp/bake
//    /tmp/bake <scratch-dir> TWAQIVision/Resources/TaiwanTerrain.bin
//
//  Output format (little endian), read by `TaiwanTerrain.swift`:
//    "TWTR"  magic
//    UInt32  version (1)
//    UInt32  columns, UInt32 rows
//    Float64 minLon, minLat, maxLon, maxLat
//    Int16   × columns × rows, row 0 = north. Metres above sea level for a
//            vertex on land, `Int16.min` for sea.
//

import CoreGraphics
import Foundation
import ImageIO

// Covers every monitoring station: Matsu to the north, Kinmen to the west,
// Orchid Island to the south-east.
let minLon = 118.1, maxLon = 122.1
let minLat = 21.85, maxLat = 26.4
let step = 0.01
let zoom = 9
let seaValue = Int16.min

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: bake <scratch-dir> <output.bin>")
    exit(1)
}
let scratch = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

// MARK: Coastline

typealias Ring = [(lon: Double, lat: Double)]

func loadTaiwanRings() throws -> [Ring] {
    let data = try Data(contentsOf: scratch.appendingPathComponent("ne_10m_admin_0_countries.geojson"))
    let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let features = root["features"] as! [[String: Any]]
    guard let taiwan = features.first(where: {
        ($0["properties"] as? [String: Any])?["ADM0_A3"] as? String == "TWN"
    }) else { fatalError("No TWN feature") }

    let geometry = taiwan["geometry"] as! [String: Any]
    let polygons: [[[[Double]]]]
    switch geometry["type"] as! String {
    case "Polygon": polygons = [geometry["coordinates"] as! [[[Double]]]]
    case "MultiPolygon": polygons = geometry["coordinates"] as! [[[[Double]]]]
    default: fatalError("Unexpected geometry")
    }
    // Even-odd over every ring, so holes need no special casing.
    return polygons.flatMap { $0 }.map { ring in ring.map { (lon: $0[0], lat: $0[1]) } }
}

struct BoundedRing {
    let points: Ring
    let minLon, maxLon, minLat, maxLat: Double

    init(_ points: Ring) {
        self.points = points
        minLon = points.map(\.lon).min()!
        maxLon = points.map(\.lon).max()!
        minLat = points.map(\.lat).min()!
        maxLat = points.map(\.lat).max()!
    }

    func crossings(lon: Double, lat: Double) -> Int {
        guard lat >= minLat, lat <= maxLat, lon <= maxLon else { return 0 }
        var count = 0
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i], b = points[j]
            if (a.lat > lat) != (b.lat > lat),
               lon < (b.lon - a.lon) * (lat - a.lat) / (b.lat - a.lat) + a.lon {
                count += 1
            }
            j = i
        }
        return count
    }
}

// MARK: Elevation

struct Tile {
    let width: Int
    let height: Int
    let pixels: [UInt8]  // RGBA
}

var tiles: [String: Tile] = [:]

func tile(x: Int, y: Int) -> Tile? {
    let key = "\(x)_\(y)"
    if let cached = tiles[key] { return cached }
    let url = scratch.appendingPathComponent("tiles/\(zoom)_\(key).png")
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }

    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    // Device RGB with no colour matching: the channels are data, not colour.
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let loaded = Tile(width: width, height: height, pixels: pixels)
    tiles[key] = loaded
    return loaded
}

/// Elevation of one Terrarium pixel, in global pixel coordinates at `zoom`.
func terrarium(px: Int, py: Int) -> Double {
    guard let tile = tile(x: px / 256, y: py / 256) else { return 0 }
    let index = ((py % 256) * tile.width + (px % 256)) * 4
    let r = Double(tile.pixels[index]), g = Double(tile.pixels[index + 1]), b = Double(tile.pixels[index + 2])
    return r * 256 + g + b / 256 - 32768
}

func elevation(lon: Double, lat: Double) -> Double {
    let n = Double(1 << zoom) * 256
    let x = (lon + 180) / 360 * n
    let latRad = lat * .pi / 180
    let y = (1 - asinh(tan(latRad)) / .pi) / 2 * n
    let x0 = Int(x - 0.5), y0 = Int(y - 0.5)
    let fx = x - 0.5 - Double(x0), fy = y - 0.5 - Double(y0)
    let top = terrarium(px: x0, py: y0) * (1 - fx) + terrarium(px: x0 + 1, py: y0) * fx
    let bottom = terrarium(px: x0, py: y0 + 1) * (1 - fx) + terrarium(px: x0 + 1, py: y0 + 1) * fx
    return top * (1 - fy) + bottom * fy
}

// MARK: Bake

let rings = try loadTaiwanRings().map(BoundedRing.init)
let columns = Int(((maxLon - minLon) / step).rounded()) + 1
let rows = Int(((maxLat - minLat) / step).rounded()) + 1
var heights = [Int16](repeating: seaValue, count: columns * rows)
var landCount = 0
var highest = 0.0

for row in 0..<rows {
    let lat = maxLat - Double(row) * step
    for column in 0..<columns {
        let lon = minLon + Double(column) * step
        let crossings = rings.reduce(0) { $0 + $1.crossings(lon: lon, lat: lat) }
        guard crossings % 2 == 1 else { continue }
        // Low coastal plain can read slightly below zero; it's still land.
        let metres = max(0, elevation(lon: lon, lat: lat))
        heights[row * columns + column] = Int16(min(metres, Double(Int16.max)))
        landCount += 1
        highest = max(highest, metres)
    }
}

var data = Data("TWTR".utf8)
func append<T>(_ value: T) {
    withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
}
append(UInt32(1).littleEndian)
append(UInt32(columns).littleEndian)
append(UInt32(rows).littleEndian)
for value in [minLon, minLat, maxLon, maxLat] {
    append(value.bitPattern.littleEndian)
}
for value in heights {
    append(value.littleEndian)
}
try data.write(to: output)

print("\(columns)×\(rows) grid, \(landCount) land vertices, highest \(Int(highest)) m, \(data.count) bytes")
