//
//  Marker.swift
//  TWAQI
//
//  Created by kf on 2/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMaps
import SwiftUI
import UIKit

/// A map marker backed by a station reading. Only markers from the supported
/// country can be opened; the rest are drawn for context only.
protocol StationMarker: AnyObject {
    var pollutant: Pollutant { get }
    var isInteractive: Bool { get }
}

/// Opacity applied to markers outside the supported country, so it reads as
/// "context, not tappable" rather than "broken".
private let mutedMarkerOpacity: Float = 0.4

/// Ceiling for a station with no reading at the timeline's hour: grey "-",
/// faded so it reads as missing rather than as a reading.
private let missingDataMarkerOpacity: Float = 0.55

/// Everything that decides how a station's marker is drawn.
///
/// The map keeps one marker per station and, when the timeline hour, the
/// index or the readings change, only touches the markers whose appearance
/// actually changed (FOX-69). Rebuilding all of them on every hour step — each
/// with a `UILabel` the map SDK had to snapshot — made scrubbing crawl.
struct MarkerAppearance: Hashable {
    enum Shape: Hashable {
        /// The reading in a rounded pill.
        case pill(text: String, foregroundColor: UInt32)
        /// Wind mode: an arrow whose length carries the speed, rotated by
        /// `bearing` (where the wind comes *from*) to point downwind.
        case arrow(strength: Double, bearing: Double)
        /// Wind mode, no wind: a ring, so still air doesn't read as a gap.
        case calm
    }

    let shape: Shape
    /// The pollutant band's colour, `0xRRGGBB`.
    let color: UInt32
    let opacity: Float

    init(shape: Shape, color: UInt32, opacity: Float) {
        self.shape = shape
        self.color = color
        self.opacity = opacity
    }

    /// - Parameter hasData: `false` when the station has no reading at the
    ///   timeline's hour (or it hasn't loaded yet).
    init(
        pollutant: Pollutant,
        airIndexType: AirIndexTypes,
        isWindMode: Bool,
        isInteractive: Bool,
        hasData: Bool = true
    ) {
        let value = pollutant.getValue(airIndexType: airIndexType)
        // Stations that report 0.0 for the selected pollutant (many don't
        // measure every one) score as `.unknown` and draw grey.
        let airStatus = AirStatuses.checkAirStatus(airIndexType: airIndexType, value: value)
        color = airStatus.getColor()

        var opacity = isInteractive ? 1 : mutedMarkerOpacity
        if !hasData {
            opacity = min(opacity, missingDataMarkerOpacity)
        }
        self.opacity = opacity

        if isWindMode {
            let wind = pollutant.wind
            shape = wind.isCalm
                ? .calm
                : .arrow(strength: wind.strengthFraction, bearing: wind.direction)
        } else {
            shape = .pill(
                text: value != 0 ? value.format(f: airIndexType.getFormat()) : "-",
                foregroundColor: airStatus.getForegroundColor()
            )
        }
    }
}

/// One station on the map, kept across redraws and updated in place.
///
/// Two looks, picked by `MarkerAppearance.Shape`:
///
/// - **Pill:** the selected index's reading on its band colour.
/// - **Wind:** a flow field, one arrow per station pointing the way the air is
///   moving. Deliberately arrow-only. This mode exists to read pollution
///   *movement* across the island at a glance, so every marker has to be
///   scannable in peripheral vision — an attempt at showing the reading
///   alongside the arrow turned the map into 80-odd numbered pills and buried
///   the flow. Colour still carries the pollutant band (following the selected
///   index chip), so the field shows where the dirty air is as well as which
///   way it is going.
final class StationMapMarker: GMSMarker, StationMarker {
    private(set) var pollutant: Pollutant
    private(set) var isInteractive: Bool
    private(set) var appearance: MarkerAppearance?

    init(pollutant: Pollutant, appearance: MarkerAppearance, isInteractive: Bool) {
        self.pollutant = pollutant
        self.isInteractive = isInteractive
        super.init()
        update(pollutant: pollutant, appearance: appearance, isInteractive: isInteractive)
    }

    /// Points the marker at a new reading. The icon is only replaced when the
    /// appearance changed, and comes from `MarkerIcons`' cache.
    func update(pollutant: Pollutant, appearance: MarkerAppearance, isInteractive: Bool) {
        self.pollutant = pollutant
        // The supported country can be resolved after the markers are drawn
        // (an offline launch going online), so taps follow it here too.
        self.isInteractive = isInteractive

        // Read by VoiceOver (and found by UI tests). No info window opens:
        // the map delegate handles every tap itself.
        let title = pollutant.displayName
        if self.title != title {
            self.title = title
        }

        // Set unconditionally on creation. An old version returned early for
        // calm stations *before* assigning a position, leaving them on
        // GMSMarker's default (0, 0) — a cluster in the Gulf of Guinea.
        let position = CLLocationCoordinate2D(latitude: pollutant.lat, longitude: pollutant.lon)
        if self.position.latitude != position.latitude || self.position.longitude != position.longitude {
            self.position = position
        }

        guard appearance != self.appearance else { return }
        self.appearance = appearance
        opacity = appearance.opacity

        switch appearance.shape {
        case .pill(let text, let foregroundColor):
            icon = MarkerIcons.pill(text: text, color: appearance.color, foregroundColor: foregroundColor)
            groundAnchor = CGPoint(x: 0.5, y: 1)
            rotation = 0
            isFlat = false

        case .arrow(let strength, let bearing):
            icon = MarkerIcons.arrow(strength: strength, color: appearance.color)
            // Centre, not the default bottom-centre: an arrow that rotates
            // about its tail swings away from the station it belongs to.
            groundAnchor = CGPoint(x: 0.5, y: 0.5)
            // Drawn pointing south, so rotating by the meteorological bearing
            // (where the wind comes *from*) leaves it pointing downwind.
            rotation = bearing
            isFlat = true

        case .calm:
            icon = MarkerIcons.calm(color: appearance.color)
            groundAnchor = CGPoint(x: 0.5, y: 0.5)
            rotation = 0
            isFlat = true
        }
    }
}

/// What a redraw has to do to bring the map's markers in line with the
/// stations it should show: which to add, which to restyle and which to take
/// off. Stations whose appearance is unchanged are left alone.
struct MarkerUpdatePlan<Key: Hashable> {
    var add: Set<Key> = []
    var update: Set<Key> = []
    var remove: Set<Key> = []

    init(current: [Key: MarkerAppearance], wanted: [Key: MarkerAppearance]) {
        for (key, appearance) in wanted {
            switch current[key] {
            case .none: add.insert(key)
            case .some(let existing) where existing != appearance: update.insert(key)
            case .some: break
            }
        }
        remove = Set(current.keys).subtracting(wanted.keys)
    }
}

/// Marker images, drawn once per look and reused.
///
/// The map SDK uploads each distinct image once; handing it the same
/// `UIImage` for every station on the same reading and band is cheaper than a
/// fresh drawing — or a `UIView` it has to snapshot — per marker per redraw.
enum MarkerIcons {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        return cache
    }()

    private static func cached(_ key: String, draw: () -> UIImage) -> UIImage {
        if let image = cache.object(forKey: key as NSString) {
            return image
        }
        let image = draw()
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// The reading in a rounded pill, 40 × 30, white hairline border.
    static func pill(text: String, color: UInt32, foregroundColor: UInt32) -> UIImage {
        cached("pill|\(text)|\(color)|\(foregroundColor)") {
            let label = UILabel(frame: CGRect(origin: .zero, size: CGSize(width: 40, height: 30)))
            label.text = text
            label.textColor = UIColor(rgb: Int(foregroundColor))
            label.font = UIFont.systemFont(ofSize: 15.0, weight: .thin)
            label.backgroundColor = UIColor(rgb: Int(color))
            label.textAlignment = NSTextAlignment.center
            label.layer.borderColor = UIColor.white.cgColor
            label.layer.borderWidth = 0.6
            label.layer.cornerRadius = 8
            label.layer.masksToBounds = true

            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            return UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { context in
                label.layer.render(in: context.cgContext)
            }
        }
    }

    /// Shaft plus chevron, cased in white so it stays legible over green
    /// terrain — the old `addShadow()` blurred grey into the glyph and turned
    /// moderate-yellow stations into brown smears.
    ///
    /// Drawn rather than built from a resized SF Symbol: `arrow.down` scaled to
    /// `windSpeed * 5` gave a 2pt speck in light air and a 40pt slab in a
    /// strong breeze, and stretching a glyph to an arbitrary box distorts its
    /// stroke.
    static func arrow(strength strengthFraction: Double, color: UInt32) -> UIImage {
        cached("arrow|\(strengthFraction)|\(color)") {
            // Square-rooted, not linear. `strengthFraction` is anchored to the
            // top of the Beaufort range this app names (8 m/s), but Taiwan's
            // stations mostly report 1–4 m/s, so a linear map squeezed almost
            // every arrow into the bottom third of the scale and the length
            // differences were invisible. The curve spreads that crowded low
            // end out.
            let strength = CGFloat(strengthFraction.squareRoot())

            // Length carries speed, and so do the head and stroke — a long
            // arrow drawn at the same weight as a short one reads as thin
            // rather than strong.
            let length = 12 + 58 * strength
            let head = 5 + 5 * strength
            let stroke = 1.8 + 1.8 * strength
            let inset = stroke + 1.5
            let size = CGSize(width: head * 2 + inset * 2, height: length + inset * 2)
            let color = UIColor(rgb: Int(color))

            return UIGraphicsImageRenderer(size: size).image { _ in
                let midX = size.width / 2
                let tip = size.height - inset

                let path = UIBezierPath()
                path.move(to: CGPoint(x: midX, y: inset))
                path.addLine(to: CGPoint(x: midX, y: tip))
                path.move(to: CGPoint(x: midX - head, y: tip - head))
                path.addLine(to: CGPoint(x: midX, y: tip))
                path.addLine(to: CGPoint(x: midX + head, y: tip - head))
                path.lineCapStyle = .round
                path.lineJoinStyle = .round

                UIColor.white.withAlphaComponent(0.85).setStroke()
                path.lineWidth = stroke + 2
                path.stroke()

                color.setStroke()
                path.lineWidth = stroke
                path.stroke()
            }
        }
    }

    /// Stations reporting no wind still belong on the field — a gap would read
    /// as missing data rather than still air.
    static func calm(color: UInt32) -> UIImage {
        cached("calm|\(color)") {
            let diameter: CGFloat = 9
            let inset: CGFloat = 2.5
            let size = CGSize(width: diameter + inset * 2, height: diameter + inset * 2)
            let color = UIColor(rgb: Int(color))

            return UIGraphicsImageRenderer(size: size).image { _ in
                let rect = CGRect(x: inset, y: inset, width: diameter, height: diameter)
                let circle = UIBezierPath(ovalIn: rect)

                UIColor.white.withAlphaComponent(0.85).setStroke()
                circle.lineWidth = 3.5
                circle.stroke()

                color.setStroke()
                circle.lineWidth = 2
                circle.stroke()
            }
        }
    }
}
