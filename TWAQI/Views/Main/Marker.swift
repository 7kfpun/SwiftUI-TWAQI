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

final class PollutantMarker: GMSMarker, StationMarker {
    let pollutant: Pollutant
    let airIndexTypeSelected: AirIndexTypes
    let isInteractive: Bool

    init(pollutant: Pollutant, airIndexTypeSelected: AirIndexTypes, isInteractive: Bool = true) {
        self.pollutant = pollutant
        self.airIndexTypeSelected = airIndexTypeSelected
        self.isInteractive = isInteractive
        super.init()

        self.opacity = isInteractive ? 1 : mutedMarkerOpacity

        self.position = CLLocationCoordinate2D(latitude: pollutant.lat, longitude: pollutant.lon)

        let value = pollutant.getValue(airIndexType: airIndexTypeSelected)

        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: airIndexTypeSelected,
            value: value
        )
        let color = UIColor(rgb: Int(airStatus.getColor()))
        let foregroundColor = UIColor(rgb: Int(airStatus.getForegroundColor()))

        let text = value.format(f: airIndexTypeSelected.getFormat())

        let label = UILabel(frame: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 40, height: 30)))
        label.text = value != 0 ? text : "-"
        label.textColor = foregroundColor
        label.font = UIFont.systemFont(ofSize: 15.0, weight: .thin)
        label.backgroundColor = color
        label.textAlignment = NSTextAlignment.center
        label.layer.borderColor = UIColor.white.cgColor
        label.layer.borderWidth = 0.6
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true

        self.iconView = label
    }
}

/// A flow field: one arrow per station, pointing the way the air is moving.
///
/// Deliberately arrow-only. This mode exists to read pollution *movement*
/// across the island at a glance, so every marker has to be scannable in
/// peripheral vision — an attempt at showing the reading alongside the arrow
/// turned the map into 80-odd numbered pills and buried the flow.
///
/// The arrow is drawn rather than built from a resized SF Symbol: `arrow.down`
/// scaled to `windSpeed * 5` gave a 2pt speck in light air and a 40pt slab in a
/// strong breeze, and stretching a glyph to an arbitrary box distorts its
/// stroke. Colour still carries the pollutant band, so the field shows where
/// the dirty air is as well as which way it is going.
final class WindDirectionMarker: GMSMarker, StationMarker {
    let pollutant: Pollutant
    let airIndexTypeSelected: AirIndexTypes
    let isInteractive: Bool

    init(pollutant: Pollutant, airIndexTypeSelected: AirIndexTypes, isInteractive: Bool = true) {
        self.pollutant = pollutant
        self.airIndexTypeSelected = airIndexTypeSelected
        self.isInteractive = isInteractive
        super.init()

        self.opacity = isInteractive ? 1 : mutedMarkerOpacity

        // Set unconditionally. The old version returned early for calm stations
        // *before* assigning a position, leaving them on GMSMarker's default
        // (0, 0) — a cluster of markers in the Gulf of Guinea.
        self.position = CLLocationCoordinate2D(latitude: pollutant.lat, longitude: pollutant.lon)

        let wind = pollutant.wind

        // Follows the selected pollutant chip, matching the pill markers and the
        // station screen — switching to PM2.5 recolours the whole map, wind
        // arrows included.
        //
        // Stations that report 0.0 for the selected pollutant (many don't
        // measure every one) score as `.unknown` and draw grey.
        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: airIndexTypeSelected,
            value: pollutant.getValue(airIndexType: airIndexTypeSelected)
        )
        let color = UIColor(rgb: Int(airStatus.getColor()))

        self.icon = wind.isCalm
            ? Self.calmImage(color: color)
            : Self.arrowImage(for: wind, color: color)

        // Centre, not the default bottom-centre: an arrow that rotates about
        // its tail swings away from the station it belongs to.
        self.groundAnchor = CGPoint(x: 0.5, y: 0.5)

        if !wind.isCalm {
            // Drawn pointing south, so rotating by the meteorological bearing
            // (where the wind comes *from*) leaves it pointing downwind.
            self.rotation = wind.direction
        }

        self.isFlat = true
    }

    /// Shaft plus chevron, cased in white so it stays legible over green
    /// terrain — the old `addShadow()` blurred grey into the glyph and turned
    /// moderate-yellow stations into brown smears.
    private static func arrowImage(for wind: Wind, color: UIColor) -> UIImage {
        // Square-rooted, not linear. `strengthFraction` is anchored to the top
        // of the Beaufort range this app names (8 m/s), but Taiwan's stations
        // mostly report 1–4 m/s, so a linear map squeezed almost every arrow
        // into the bottom third of the scale and the length differences were
        // invisible. The curve spreads that crowded low end out.
        let strength = CGFloat(wind.strengthFraction.squareRoot())

        // Length carries speed, and so do the head and stroke — a long arrow
        // drawn at the same weight as a short one reads as thin rather than
        // strong.
        let length = 12 + 58 * strength
        let head = 5 + 5 * strength
        let stroke = 1.8 + 1.8 * strength
        let inset = stroke + 1.5
        let size = CGSize(width: head * 2 + inset * 2, height: length + inset * 2)

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

    /// Stations reporting no wind still belong on the field — a gap would read
    /// as missing data rather than still air.
    private static func calmImage(color: UIColor) -> UIImage {
        let diameter: CGFloat = 9
        let inset: CGFloat = 2.5
        let size = CGSize(width: diameter + inset * 2, height: diameter + inset * 2)

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
