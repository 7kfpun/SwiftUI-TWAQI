//
//  HeatmapInterpolation.swift
//  TWAQI
//
//  TWAQ-22: estimates the index between stations for the optional heatmap
//  layer. Pure maths, no UIKit or map SDK, so it is tested directly and can
//  run on any queue.
//

import CoreGraphics
import Foundation

/// A station's reading that may feed the heatmap.
struct HeatmapSample: Equatable {
    let latitude: Double
    let longitude: Double
    let value: Double
}

/// A geographic rectangle the overlay covers.
struct HeatmapBounds: Equatable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
}

enum HeatmapInterpolation {
    /// How far colour reaches from a station. Beyond it the layer stays empty
    /// (sea, mountains, no station nearby) instead of inventing a value.
    static let maxDistanceKm: Double = 18
    /// Inside this fraction of the reach the colour is fully opaque; it then
    /// fades to nothing at the reach, so edges are soft rather than cut.
    static let solidFraction: Double = 0.55
    /// Inverse-distance weighting power.
    static let power: Double = 2

    private static let kmPerDegree = 111.32

    /// Samples that may contribute: a missing reading (zero or negative, NaN,
    /// infinite) is dropped, never averaged in as a clean-air zero.
    static func usable(_ samples: [HeatmapSample]) -> [HeatmapSample] {
        samples.filter { $0.value.isFinite && $0.value > 0 }
    }

    /// Estimated value and coverage at one point, or nil when no usable
    /// station is within `maxDistanceKm`.
    static func estimate(
        latitude: Double,
        longitude: Double,
        samples: [HeatmapSample],
        maxDistanceKm: Double = HeatmapInterpolation.maxDistanceKm
    ) -> (value: Double, coverage: Double)? {
        let cosLat = cos(latitude * .pi / 180)
        var weightSum = 0.0
        var weighted = 0.0
        var nearest = Double.infinity
        for sample in samples {
            let dy = (sample.latitude - latitude) * kmPerDegree
            let dx = (sample.longitude - longitude) * kmPerDegree * cosLat
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance <= maxDistanceKm else { continue }
            if distance < 0.001 { return (sample.value, 1) }
            nearest = min(nearest, distance)
            let weight = 1 / pow(distance, power)
            weightSum += weight
            weighted += weight * sample.value
        }
        guard weightSum > 0 else { return nil }
        return (weighted / weightSum, coverage(atDistance: nearest, maxDistanceKm: maxDistanceKm))
    }

    /// 1 near a station, fading to 0 at the reach.
    static func coverage(atDistance distance: Double, maxDistanceKm: Double = HeatmapInterpolation.maxDistanceKm) -> Double {
        let solid = maxDistanceKm * solidFraction
        if distance <= solid { return 1 }
        if distance >= maxDistanceKm { return 0 }
        return 1 - (distance - solid) / (maxDistanceKm - solid)
    }

    /// Samples the field on a `width` x `height` grid over `bounds`, row 0 at
    /// the north edge. Cells out of reach are nil.
    static func grid(
        samples: [HeatmapSample],
        bounds: HeatmapBounds,
        width: Int,
        height: Int,
        maxDistanceKm: Double = HeatmapInterpolation.maxDistanceKm
    ) -> [(value: Double, coverage: Double)?] {
        let usableSamples = usable(samples)
        guard width > 0, height > 0, !usableSamples.isEmpty else {
            return Array(repeating: nil, count: max(0, width * height))
        }
        // Only stations that can reach the box matter; keeps the inner loop short.
        let margin = maxDistanceKm / kmPerDegree
        let near = usableSamples.filter {
            $0.latitude >= bounds.south - margin && $0.latitude <= bounds.north + margin
                && $0.longitude >= bounds.west - margin * 1.2 && $0.longitude <= bounds.east + margin * 1.2
        }
        func mercatorY(_ latitude: Double) -> Double { log(tan(.pi / 4 + latitude * .pi / 360)) }
        let yNorth = mercatorY(bounds.north)
        let ySouth = mercatorY(bounds.south)
        var cells = [(value: Double, coverage: Double)?](repeating: nil, count: width * height)
        for row in 0..<height {
            // Rows are even in Web Mercator, as the map stretches the image.
            let y = yNorth - (Double(row) + 0.5) / Double(height) * (yNorth - ySouth)
            let latitude = (2 * atan(exp(y)) - .pi / 2) * 180 / .pi
            for column in 0..<width {
                let longitude = bounds.west + (Double(column) + 0.5) / Double(width) * (bounds.east - bounds.west)
                cells[row * width + column] = estimate(
                    latitude: latitude, longitude: longitude, samples: near, maxDistanceKm: maxDistanceKm
                )
            }
        }
        return cells
    }

    /// Overlay strength for a map zoom: full at country zoom, fading as
    /// markers become readable, gone when zoomed in close.
    static func opacity(forZoom zoom: Float) -> Float {
        let full: Float = 8.0
        let none: Float = 12.0
        let strongest: Float = 0.85
        if zoom <= full { return strongest }
        if zoom >= none { return 0 }
        return strongest * (none - zoom) / (none - full)
    }

    /// Renders the grid into an RGBA image. `color` maps a value to `0xRRGGBB`.
    static func image(
        cells: [(value: Double, coverage: Double)?],
        width: Int,
        height: Int,
        color: (Double) -> UInt32
    ) -> CGImage? {
        guard width > 0, height > 0, cells.count == width * height else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (index, cell) in cells.enumerated() {
            guard let cell, cell.coverage > 0 else { continue }
            let rgb = color(cell.value)
            let alpha = cell.coverage
            // Premultiplied alpha.
            pixels[index * 4] = UInt8(Double((rgb >> 16) & 0xFF) * alpha)
            pixels[index * 4 + 1] = UInt8(Double((rgb >> 8) & 0xFF) * alpha)
            pixels[index * 4 + 2] = UInt8(Double(rgb & 0xFF) * alpha)
            pixels[index * 4 + 3] = UInt8(255 * alpha)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
