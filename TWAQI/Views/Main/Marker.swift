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
    let selectedIndex: Constants.AirIndexTypes

    init(pollutant: Pollutant, selectedIndex: Constants.AirIndexTypes) {
        self.pollutant = pollutant
        self.selectedIndex = selectedIndex
        super.init()

        guard let dLatitude: Double = Double(pollutant.latitude),
            let dLongitude: Double = Double(pollutant.longitude) else {
                return
        }
        self.position = CLLocationCoordinate2D(latitude: dLatitude, longitude: dLongitude)

        let airStatus = Constants.AirStatuses.checkAirStatus(
            airIndexType: selectedIndex,
            value: pollutant.getValue(airIndexType: selectedIndex)
        )
        let color = UIColor(rgb: Int(airStatus.getColor()))
        let foregroundColor = UIColor(rgb: Int(airStatus.getForegroundColor()))

//        let label = UILabel(frame: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 40, height: 30)))
//        label.text = pollutant.aqi
//        label.textColor = foregroundColor
//        label.font = UIFont.systemFont(ofSize: 15.0, weight: .thin)
//        label.backgroundColor = color
//        label.textAlignment = NSTextAlignment.center
//        label.layer.borderColor = UIColor.white.cgColor
//        label.layer.borderWidth = 1.0
//        label.layer.cornerRadius = 8
//        label.layer.masksToBounds = true

        let label = UIButton(frame: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 40, height: 30)))
        label.setTitle(pollutant.aqi, for: .normal)
        label.setTitleColor(foregroundColor, for: .normal)
        label.titleLabel?.font = .systemFont(ofSize: 15, weight: .thin)
        label.backgroundColor = color
        label.layer.borderColor = UIColor.white.cgColor
        label.layer.borderWidth = 0.6
        label.layer.cornerRadius = 8
//        label.addTarget(self, action: #selector(changeIndex), for: .touchUpInside)

        self.iconView = label
    }
}

final class WindDirectionMarker: GMSMarker {
    let pollutant: Pollutant
    let selectedIndex: Constants.AirIndexTypes

    init(pollutant: Pollutant, selectedIndex: Constants.AirIndexTypes) {
        self.pollutant = pollutant
        self.selectedIndex = selectedIndex
        super.init()

        guard let dLatitude: Double = Double(pollutant.latitude),
            let dLongitude: Double = Double(pollutant.longitude),
            let dWindDirection: Double = Double(pollutant.windDirection),
            let dWindSpeed: Double = Double(pollutant.windSpeed) else {
                return
        }
        self.position = CLLocationCoordinate2D(latitude: dLatitude, longitude: dLongitude)

        let airStatus = Constants.AirStatuses.checkAirStatus(
            airIndexType: selectedIndex,
            value: pollutant.getValue(airIndexType: selectedIndex)
        )
        let color = UIColor(rgb: Int(airStatus.getColor()))

        let boldConfig = UIImage.SymbolConfiguration(weight: .bold)
        let icon = UIImage(systemName: "arrow.down", withConfiguration: boldConfig)!
            .withTintColor(color, renderingMode: .alwaysOriginal)
            .resizeImage(targetSize: CGSize(width: dWindSpeed * 5, height: dWindSpeed * 5))
            .addShadow()
        self.icon = icon
        self.rotation = dWindDirection
    }
}
