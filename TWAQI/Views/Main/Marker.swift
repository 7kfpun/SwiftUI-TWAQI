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

        let dWindSpeed = pollutant.windSpeed

        if dWindSpeed == 0 {
            return
        }

        self.position = CLLocationCoordinate2D(latitude: pollutant.lat, longitude: pollutant.lon)

        let airStatus = AirStatuses.checkAirStatus(
            airIndexType: airIndexTypeSelected,
            value: pollutant.getValue(airIndexType: airIndexTypeSelected)
        )
        let color = UIColor(rgb: Int(airStatus.getColor()))

        let boldConfig = UIImage.SymbolConfiguration(weight: .bold)
        let icon = UIImage(systemName: "arrow.down", withConfiguration: boldConfig)!
            .withTintColor(color, renderingMode: .alwaysOriginal)
            .resizeImage(targetSize: CGSize(width: dWindSpeed * 5, height: dWindSpeed * 5))
            .addShadow()
        
        self.icon = icon
        self.rotation = pollutant.windDirection
        self.isFlat = true
    }
}
