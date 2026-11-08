//
//  LocateMe.swift
//  TWAQI
//
//  FOX-185: the map's "locate me" button and the user's position marker.
//
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation

/// The three states of the locate-me button.
enum LocateMeMode: Equatable {
    /// The map is where the user left it.
    case off
    /// Centred on the user once; moving the position doesn't move the map.
    case centred
    /// The map follows the user's position.
    case following

    /// What one tap on the button does: off → centred → following, and a tap
    /// while following centres on the user again.
    var afterTap: LocateMeMode {
        switch self {
        case .off: return .centred
        case .centred: return .following
        case .following: return .centred
        }
    }

    /// The user dragged, pinched or rotated the map: stop centring and following.
    var afterGesture: LocateMeMode { .off }
}

/// What a tap on the button does for a given location authorization.
enum LocateMeAccess: Equatable {
    /// Never asked: ask now, on this tap.
    case ask
    case allowed
    /// Denied or restricted: explain how to turn it on in Settings.
    case explain

    init(status: CLAuthorizationStatus, servicesEnabled: Bool = true) {
        guard servicesEnabled else { self = .explain; return }
        switch status {
        case .notDetermined: self = .ask
        case .authorizedWhenInUse, .authorizedAlways: self = .allowed
        default: self = .explain
        }
    }
}

enum LocateMe {
    static let minZoom: Float = 9
    static let maxZoom: Float = 15

    /// The station closest to a point, with its distance in metres.
    static func nearest(
        to origin: CLLocationCoordinate2D,
        in points: [(id: Int, latitude: Double, longitude: Double)]
    ) -> (id: Int, distance: CLLocationDistance)? {
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return points
            .map { (id: $0.id, distance: here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .min { $0.distance < $1.distance }
    }

    /// A zoom that shows the user and the nearest station together, with some
    /// room around them. `nil` distance (no stations loaded yet) gives a
    /// neighbourhood zoom.
    static func zoom(
        latitude: Double,
        nearestStationDistance: CLLocationDistance?,
        viewHalfWidthPoints: Double = 180
    ) -> Float {
        guard let distance = nearestStationDistance, distance > 0 else { return 13 }
        // Web-Mercator: metres per point at zoom z is 156543.03 * cos(lat) / 2^z.
        let wanted = distance * 1.6
        let metresAtZoomZero = 156_543.03 * cos(latitude * .pi / 180) * viewHalfWidthPoints
        let zoom = log2(metresAtZoomZero / wanted)
        return Float(min(max(zoom, Double(minZoom)), Double(maxZoom)))
    }

    /// Radius of the accuracy halo: the reported accuracy, with a floor so the
    /// dot never sits in a halo too small to see, and a cap so a poor fix
    /// doesn't flood the map. `nil` for an invalid (negative) accuracy.
    static func haloRadius(horizontalAccuracy: CLLocationAccuracy) -> CLLocationDistance? {
        guard horizontalAccuracy >= 0 else { return nil }
        return min(max(horizontalAccuracy, 20), 1_500)
    }

    /// A heading from the compass, or `nil` while it is unavailable or uncalibrated.
    static func heading(from heading: CLHeading) -> CLLocationDirection? {
        let value = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        return heading.headingAccuracy >= 0 && value >= 0 ? value : nil
    }
}
