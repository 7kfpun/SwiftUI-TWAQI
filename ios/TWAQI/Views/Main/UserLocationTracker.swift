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
import UIKit

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
        manager.headingFilter = 5
    }

    /// Keeps the compass heading relative to the top of the screen, not the portrait edge.
    func setInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        manager.headingOrientation = LocateMe.headingOrientation(for: orientation)
    }

    /// `authorizationStatus` alone: it reads `.denied` while Location Services
    /// are off, so no `locationServicesEnabled()` call (it blocks the main thread).
    var access: LocateMeAccess {
        LocateMeAccess(status: manager.authorizationStatus)
    }

    /// The map is on screen, and the app is in the foreground. Updates run
    /// only while both hold (and permission is given); see `LocateMe.shouldRunUpdates`.
    private var visible = false
    private var appActive = true
    private var running = false

    func setVisible(_ visible: Bool) {
        self.visible = visible
        sync()
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        sync()
    }

    /// Starts updates when permission is already given and the map is showing;
    /// does nothing otherwise.
    func startIfAllowed() { sync() }

    func stop() {
        running = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func sync() {
        guard LocateMe.shouldRunUpdates(visible: visible, appActive: appActive, access: access) else {
            if running { stop() }
            return
        }
        if !running {
            running = true
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        }
        // On a restart this also hands the following map the newest known fix.
        if let last = manager.location, last.timestamp > (location?.timestamp ?? .distantPast) {
            location = last
            onLocation?(last)
        }
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
        // A fix that arrives after a stop (revoked, hidden, backgrounded) is dropped.
        guard running, let latest = locations.last else { return }
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
