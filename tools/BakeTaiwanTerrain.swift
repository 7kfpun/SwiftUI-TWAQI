//
//  BakeTaiwanTerrain.swift
//  tools
//
//  Bakes the terrain the visionOS app builds its 3D Taiwan from: a signed
//  elevation grid for the mesh, and the texture painted over it — land in
//  relief, the sea shaded by depth.
//
//  Inputs (download into an empty scratch directory):
//    - Natural Earth 10m admin-0 countries (public domain), for the coastline:
//      https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson
//    - Terrarium elevation tiles at zoom 9 (Mapzen / AWS Terrain Tiles), as
//      `tiles/9_<x>_<y>.png`, covering the bounding box below. They carry
//      bathymetry as well as land:
//      https://s3.amazonaws.com/elevation-tiles-prod/terrarium/9/<x>/<y>.png
//
//  Usage:
//    swiftc -O tools/BakeTaiwanTerrain.swift -o /tmp/bake
//    /tmp/bake <scratch-dir> TWAQIVision/Resources
//
//  Writes, into that directory:
//
//  TaiwanTerrain.bin (little endian), read by `TaiwanTerrain.swift`:
//    "TWTR"  magic
//    UInt32  version (2)
//    UInt32  columns, UInt32 rows
//    Float64 minLon, minLat, maxLon, maxLat
//    Int16   × columns × rows, row 0 = north. Metres: 0 or more is land
//            (inside the coastline), negative is sea depth.
//
//  TaiwanRelief.png: the texture for the island's surface and the sea, at
//  `oversample` × the grid. Hillshading assumes the app's default vertical
//  exaggeration, `reliefExaggeration`.
//

import CoreGraphics
import Foundation
import ImageIO
import simd
import UniformTypeIdentifiers

// The app shows a round diorama: a disc of ocean centred here, wide enough
// for every monitoring station — Matsu to the north, Kinmen to the west,
// Orchid Island (the farthest, 275 km out) to the south-east. The grid is the
// square around that disc.
let centreLon = 120.1, centreLat = 24.125
let discRadiusKm = 285.0
let kmPerDegreeLat = 110.574
let kmPerDegreeLon = 111.320 * cos(centreLat * .pi / 180)
let minLon = centreLon - discRadiusKm / kmPerDegreeLon, maxLon = centreLon + discRadiusKm / kmPerDegreeLon
let minLat = centreLat - discRadiusKm / kmPerDegreeLat, maxLat = centreLat + discRadiusKm / kmPerDegreeLat
let step = 0.01
let zoom = 9
let oversample = 3
/// Must match `TaiwanTerrain`'s default `verticalExaggeration`.
let reliefExaggeration = 8.0

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: bake <scratch-dir> <output-directory>")
    exit(1)
}
let scratch = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])

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
var heights = [Int16](repeating: 0, count: columns * rows)
var landCount = 0
var highest = 0.0, deepest = 0.0

for row in 0..<rows {
    let lat = maxLat - Double(row) * step
    for column in 0..<columns {
        let lon = minLon + Double(column) * step
        let metres = elevation(lon: lon, lat: lat)
        let crossings = rings.reduce(0) { $0 + $1.crossings(lon: lon, lat: lat) }
        let insideDisc = hypot((lon - centreLon) * kmPerDegreeLon, (lat - centreLat) * kmPerDegreeLat) <= discRadiusKm
        let value: Double
        if crossings % 2 == 1, insideDisc {
            // Low coastal plain can read slightly below zero; it's still land.
            value = max(0, metres)
            landCount += 1
            highest = max(highest, value)
        } else {
            // The tiles are coarser than the coastline: water they call land
            // is shallow sea.
            value = min(-1, metres)
            deepest = min(deepest, value)
        }
        heights[row * columns + column] = Int16(max(min(value, Double(Int16.max)), Double(Int16.min)))
    }
}

var data = Data("TWTR".utf8)
func append<T>(_ value: T) {
    withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
}
append(UInt32(2).littleEndian)
append(UInt32(columns).littleEndian)
append(UInt32(rows).littleEndian)
// The extent the grid actually covers: the radius rarely lands on a whole
// number of steps. Rows run south from maxLat, columns east from minLon.
for value in [minLon, maxLat - Double(rows - 1) * step, minLon + Double(columns - 1) * step, maxLat] {
    append(value.bitPattern.littleEndian)
}
for value in heights {
    append(value.littleEndian)
}
try data.write(to: outputDirectory.appendingPathComponent("TaiwanTerrain.bin"))

// MARK: Texture

/// Muted on land so the AQI colours stay the loudest thing on the island.
let landRamp: [(metres: Double, color: SIMD3<Double>)] = [
    (0, SIMD3(0.56, 0.62, 0.52)),
    (400, SIMD3(0.64, 0.67, 0.55)),
    (1200, SIMD3(0.72, 0.69, 0.60)),
    (2400, SIMD3(0.80, 0.78, 0.74)),
    (3600, SIMD3(0.96, 0.96, 0.96)),
]

/// Turquoise over the shelf, deepening to navy over the Pacific trench.
let seaRamp: [(metres: Double, color: SIMD3<Double>)] = [
    (0, SIMD3(0.45, 0.76, 0.80)),
    (60, SIMD3(0.29, 0.62, 0.74)),
    (200, SIMD3(0.17, 0.46, 0.66)),
    (1000, SIMD3(0.10, 0.31, 0.53)),
    (3000, SIMD3(0.06, 0.19, 0.39)),
    (6000, SIMD3(0.03, 0.11, 0.26)),
]

func ramp(_ stops: [(metres: Double, color: SIMD3<Double>)], _ metres: Double) -> SIMD3<Double> {
    guard let upper = stops.firstIndex(where: { $0.metres >= metres }) else { return stops.last!.color }
    guard upper > 0 else { return stops[0].color }
    let low = stops[upper - 1], high = stops[upper]
    let t = (metres - low.metres) / (high.metres - low.metres)
    return low.color + (high.color - low.color) * t
}

func gridValue(_ column: Int, _ row: Int) -> Double {
    Double(heights[min(row, rows - 1) * columns + min(column, columns - 1)])
}

/// Bilinear over the grid, in grid units.
func sample(_ column: Double, _ row: Double) -> (metres: Double, landness: Double) {
    let c0 = Int(column), r0 = Int(row)
    let fx = column - Double(c0), fy = row - Double(r0)
    var metres = 0.0, landness = 0.0
    for (dc, dr, w) in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)] {
        let value = gridValue(c0 + dc, r0 + dr)
        metres += value * w
        landness += (value >= 0 ? 1 : 0) * w
    }
    return (metres, landness)
}

let width = (columns - 1) * oversample + 1
let height = (rows - 1) * oversample + 1
var pixels = [UInt8](repeating: 255, count: width * height * 4)
let texelStep = 1 / Double(oversample)
/// Ground size of one texel, in metres.
let texelMetres = step * 110_574 * texelStep
let light = simd_normalize(SIMD3<Double>(-1, 1.4, -1))

for y in 0..<height {
    for x in 0..<width {
        let column = Double(x) * texelStep, row = Double(y) * texelStep
        let here = sample(column, row)
        let isLand = here.landness >= 0.5
        // Land shades with the mesh's exaggeration; the seafloor far more
        // gently, as relief seen through water.
        let exaggeration = isLand ? reliefExaggeration : 0.6
        func surface(_ c: Double, _ r: Double) -> Double {
            let value = sample(min(max(c, 0), Double(columns - 1)), min(max(r, 0), Double(rows - 1))).metres
            return isLand ? max(0, value) : min(0, value)
        }
        let normal = simd_normalize(SIMD3(
            -(surface(column + texelStep, row) - surface(column - texelStep, row)) * exaggeration / (2 * texelMetres),
            1,
            -(surface(column, row + texelStep) - surface(column, row - texelStep)) * exaggeration / (2 * texelMetres)
        ))
        let lit = max(0, simd_dot(normal, light))
        let color = isLand
            ? ramp(landRamp, max(0, here.metres)) * (0.72 + 0.4 * lit)
            : ramp(seaRamp, max(0, -here.metres)) * (0.9 + 0.15 * lit)
        let offset = (y * width + x) * 4
        pixels[offset] = UInt8(min(255, max(0, color.x * 255)))
        pixels[offset + 1] = UInt8(min(255, max(0, color.y * 255)))
        pixels[offset + 2] = UInt8(min(255, max(0, color.z * 255)))
    }
}

let image = CGImage(
    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
    provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: true,
    intent: .defaultIntent
)!
let textureURL = outputDirectory.appendingPathComponent("TaiwanRelief.png")
let destination = CGImageDestinationCreateWithURL(textureURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(textureURL.path)") }

print("\(columns)×\(rows) grid, \(landCount) land vertices, highest \(Int(highest)) m, deepest \(Int(-deepest)) m")
print("TaiwanTerrain.bin \(data.count) bytes; TaiwanRelief.png \(width)×\(height)")
