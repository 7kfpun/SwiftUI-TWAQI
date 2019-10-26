//
//  GoogleMapView.swift
//  TWAQI
//
//  Created by kf on 24/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import GoogleMaps
import SwiftUI
import UIKit

final class PollutantMarker: GMSMarker {
    let pollutant: Pollutant

    init(pollutant: Pollutant) {
        self.pollutant = pollutant
        super.init()

        guard let dLatitude: Double = Double(pollutant.latitude),
            let dLongitude: Double = Double(pollutant.longitude) else {
           return
        }
        self.position = CLLocationCoordinate2D(latitude: dLatitude, longitude: dLongitude)

        let airStatus = Constants.AirIndexTypes.aqi.getAirStatus(value: Int(pollutant.aqi) ?? 0)
        let color = UIColor(rgb: Int(airStatus.getColor()))
        let foregroundColor = UIColor(rgb: Int(airStatus.getForegroundColor()))

        let label = UILabel(frame: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 40, height: 30)))
        label.text = pollutant.aqi
        label.textColor = foregroundColor
        label.font = UIFont.systemFont(ofSize: 15.0, weight: .thin)
        label.backgroundColor = color
        label.textAlignment = NSTextAlignment.center
        label.layer.borderColor = UIColor.white.cgColor
        label.layer.borderWidth = 1.0
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        self.iconView = label
    }
}

final class WindDirectionMarker: GMSMarker {
    let pollutant: Pollutant

    init(pollutant: Pollutant) {
        self.pollutant = pollutant
        super.init()

        guard let dLatitude: Double = Double(pollutant.latitude),
            let dLongitude: Double = Double(pollutant.longitude),
            let dWindDirection: Double = Double(pollutant.windDirection),
            let dWindSpeed: Double = Double(pollutant.windSpeed) else {
           return
        }
        self.position = CLLocationCoordinate2D(latitude: dLatitude, longitude: dLongitude)

        let airStatus = Constants.AirIndexTypes.aqi.getAirStatus(value: Int(pollutant.aqi) ?? 0)
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

struct GoogleMapView: UIViewRepresentable {
    let pollutants: Pollutants
    let isWindMode: Bool

    /// Creates a `UIView` instance to be presented.
    func makeUIView(context: Self.Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: 23.49, longitude: 120.96, zoom: 7.9)
        let mapView = GMSMapView.map(withFrame: CGRect.zero, camera: camera)
        mapView.isMyLocationEnabled = true
        mapView.settings.compassButton = true

        return mapView
    }

    /// Updates the presented `UIView` (and coordinator) to the latest configuration.
    func updateUIView(_ mapView: GMSMapView, context: Self.Context) {
        mapView.clear()

        pollutants.forEach { pollutant in
            var pollutantMarker: GMSMarker
            if isWindMode {
                pollutantMarker = WindDirectionMarker(pollutant: pollutant)
            } else {
                pollutantMarker = PollutantMarker(pollutant: pollutant)
            }
            pollutantMarker.map = mapView
        }
    }
}

//struct GoogleMapView_Previews: PreviewProvider {
//    static var previews: some View {
//        GoogleMapView()
//    }
//}
