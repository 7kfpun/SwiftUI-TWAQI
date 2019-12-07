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

final class PollutantMarker: GMSMarker {
    let pollutant: Pollutant
    let airIndexTypeSelected: AirIndexTypes

    init(pollutant: Pollutant, airIndexTypeSelected: AirIndexTypes) {
        self.pollutant = pollutant
        self.airIndexTypeSelected = airIndexTypeSelected
        super.init()

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

final class WindDirectionMarker: GMSMarker {
    let pollutant: Pollutant
    let airIndexTypeSelected: AirIndexTypes

    init(pollutant: Pollutant, airIndexTypeSelected: AirIndexTypes) {
        self.pollutant = pollutant
        self.airIndexTypeSelected = airIndexTypeSelected
        super.init()

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
