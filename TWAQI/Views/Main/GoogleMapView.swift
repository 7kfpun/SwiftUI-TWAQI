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

struct GoogleMapView: UIViewRepresentable {
    let pollutants: Pollutants
    let isWindMode: Bool

    var selectedIndex: AirIndexTypes = AirIndexTypes.aqi

    /// Creates a `UIView` instance to be presented.
    func makeUIView(context: Self.Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: 23.49, longitude: 120.96, zoom: 7.9)
        let mapView = GMSMapView.map(withFrame: CGRect.zero, camera: camera)
        mapView.isMyLocationEnabled = true
        mapView.settings.compassButton = true
        mapView.padding = UIEdgeInsets(top: 0, left: 0, bottom: 130, right: 8)

        do {
            // Set the map style by passing a valid JSON string.
            mapView.mapStyle = try GMSMapStyle(jsonString: GoogleMapStyles.dark.rawValue)
        } catch {
            NSLog("One or more of the map styles failed to load. \(error)")
        }

        return mapView
    }

    /// Updates the presented `UIView` (and coordinator) to the latest configuration.
    func updateUIView(_ mapView: GMSMapView, context: Self.Context) {
        mapView.clear()

        pollutants.forEach { pollutant in
            var pollutantMarker: GMSMarker
            if isWindMode {
                pollutantMarker = WindDirectionMarker(pollutant: pollutant, selectedIndex: self.selectedIndex)
            } else {
                pollutantMarker = PollutantMarker(pollutant: pollutant, selectedIndex: self.selectedIndex)
            }
            pollutantMarker.map = mapView
        }

        if let mylocation = mapView.myLocation {
            print("User's location: \(mylocation)")
        } else {
            print("User's location is unknown")
        }
    }
}

//struct GoogleMapView_Previews: PreviewProvider {
//    static var previews: some View {
//        GoogleMapView()
//    }
//}
