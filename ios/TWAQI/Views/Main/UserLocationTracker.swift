//
//  UserLocationTracker.swift
//  TWAQI
//
//  FOX-185: the map's own location updates (position, accuracy, compass).
//  It never asks for permission by itself: only `requestAccess()` does, from
//  a tap on the locate-me button. The welcome flow asks on its own step.
//
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation

final class UserLocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    private(set) var heading: CLLocationDirection?

    var onLocation: ((CLLocation) -> Void)?
    var onHeading: ((CLLocationDirection?) -> Void)?
    var onAccessChange: ((LocateMeAccess) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
    }

    var access: LocateMeAccess {
        LocateMeAccess(status: manager.authorizationStatus, servicesEnabled: CLLocationManager.locationServicesEnabled())
    }

    /// Starts updates when permission is already given; does nothing otherwise.
    func startIfAllowed() {
        guard access == .allowed else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        if let last = manager.location, location == nil {
            location = last
            onLocation?(last)
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// The one place that shows the system permission prompt.
    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startIfAllowed()
        onAccessChange?(access)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        onLocation?(latest)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = LocateMe.heading(from: newHeading)
        onHeading?(heading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keeps the last position; the next update replaces it.
    }
}
