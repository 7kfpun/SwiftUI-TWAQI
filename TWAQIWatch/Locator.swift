//
//  Locator.swift
//  TWAQIWatch
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation

/// One-shot location for picking the home station.
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // A station is several kilometres from the next; a coarse fix is
        // faster and kinder to the battery.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// `nil` when the reader declines, or no fix arrives.
    func current() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        default:
            break
        }
        guard continuation == nil else { return nil }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Also fires once when the delegate is set; only answer a pending request.
            guard continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .notDetermined:
                return
            case .denied, .restricted:
                finish(nil)
            default:
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}
