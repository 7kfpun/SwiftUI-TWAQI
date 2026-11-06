//
//  StationLocationView.swift
//  TWAQI
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import MapKit
import SwiftUI

/// Where the monitoring station physically is: a small map, the address and
/// the coordinates.
///
/// Fixed metadata, not a reading — so it sits at the foot of the screen, below
/// everything that changes hour to hour, rather than sharing a heading with the
/// live wind measurement as it used to.
struct StationLocationView: View {
    var address: String?
    var coordinateText: String
    /// The address as it should read — translated on device outside Chinese.
    /// Nil shows `address`, the API's Chinese.
    var displayAddress: String?
    /// Nil when the API gave no position (0, 0): no map, nothing to open.
    var coordinate: CLLocationCoordinate2D?
    /// Read by VoiceOver on the map and used as the pin's name in Apple Maps.
    var stationName: String
    /// The station's AQI band colour, for the marker on the map; grey for a
    /// station with no current reading.
    var markerColor: Color

    @Environment(\.openURL) private var openURL

    init(
        address: String?,
        coordinateText: String,
        lat: Double,
        lon: Double,
        stationName: String,
        aqi: Double?
    ) {
        self.address = address
        self.coordinateText = coordinateText
        self.coordinate = StationMiniMap.coordinate(lat: lat, lon: lon)
        self.stationName = stationName
        self.markerColor = aqi.map { Color(AirStatuses.checkAirStatus(airIndexType: .aqi, value: $0).getColor()) }
            ?? Color(UIColor.systemGray)
    }

    init(pollutant: Pollutant) {
        self.init(
            address: pollutant.address,
            coordinateText: pollutant.coordinateText,
            lat: pollutant.lat,
            lon: pollutant.lon,
            stationName: pollutant.displayName,
            aqi: pollutant.aqi
        )
    }

    /// Nothing to show for a station the API gave no address or coordinates.
    var hasContent: Bool {
        address != nil || !coordinateText.isEmpty
    }

    /// Opens the station in Apple Maps; nil without a position.
    private var mapsURL: URL? {
        coordinate.flatMap { StationMiniMap.appleMapsURL(coordinate: $0, name: stationName) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Details.location")

            if let coordinate = coordinate, let url = mapsURL {
                Button(action: { openURL(url) }) {
                    StationMiniMap(coordinate: coordinate, markerColor: markerColor)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(Text("Details.map_of \(stationName)"))
                .accessibilityHint(Text("Details.open_in_maps"))
            }

            if let address = displayAddress ?? address {
                if let url = mapsURL {
                    Button(action: { openURL(url) }) {
                        InfoRow(icon: "mappin.circle", title: "Details.address", value: address)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityHint(Text("Details.open_in_maps"))
                } else {
                    InfoRow(icon: "mappin.circle", title: "Details.address", value: address)
                }
            }

            if !coordinateText.isEmpty {
                InfoRow(
                    icon: "location",
                    title: "Details.coordinates",
                    value: coordinateText
                )
            }
        }
        .padding(.horizontal)
    }
}

/// A still picture of the streets around the station with its marker in the
/// middle (Android's `StationMiniMap`). An `MKMapSnapshotter` image rather
/// than a live `Map`: nothing to pan inside a scrolling page, and one image
/// is cheaper than a map view. Redrawn for dark mode; kept in memory per
/// station, size and appearance so coming back to a station doesn't redraw.
struct StationMiniMap: View {
    let coordinate: CLLocationCoordinate2D
    let markerColor: Color

    static let height: CGFloat = 160
    /// About a neighbourhood across (Android uses zoom 14).
    static let spanMeters: CLLocationDistance = 1500

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    @State private var snapshot: Snapshot?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { proxy in
            let key = SnapshotKey(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                width: proxy.size.width.rounded(),
                height: Self.height,
                isDark: colorScheme == .dark,
                scale: displayScale
            )

            ZStack {
                Color(UIColor.secondarySystemBackground)

                if let snapshot = snapshot, snapshot.key == key {
                    Image(uiImage: snapshot.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                marker
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: key) {
                guard key.width > 0 else { return }
                if let cached = Self.cache.object(forKey: key.cacheKey) {
                    snapshot = Snapshot(key: key, image: cached)
                    return
                }
                guard let image = await Self.render(key), !Task.isCancelled else { return }
                Self.cache.setObject(image, forKey: key.cacheKey)
                snapshot = Snapshot(key: key, image: image)
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    /// The map is centred on the station, so its marker sits in the middle.
    private var marker: some View {
        Circle()
            .fill(markerColor)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }

    // MARK: - Pure helpers (tested)

    /// The station's position, or nil when there isn't a usable one: the API
    /// sends 0, 0 for a station it has no position for.
    static func coordinate(lat: Double, lon: Double) -> CLLocationCoordinate2D? {
        guard lat.isFinite, lon.isFinite, !(lat == 0 && lon == 0) else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    /// `https://maps.apple.com/?ll=25.129167,121.760056&q=Keelung`: Apple Maps
    /// drops a pin named `q` at `ll`.
    static func appleMapsURL(coordinate: CLLocationCoordinate2D, name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        var items = [
            URLQueryItem(
                name: "ll",
                value: String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
            ),
        ]
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            items.append(URLQueryItem(name: "q", value: name))
        }
        components.queryItems = items
        return components.url
    }

    static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: spanMeters, longitudinalMeters: spanMeters)
    }

    // MARK: - Snapshot

    private struct Snapshot {
        let key: SnapshotKey
        let image: UIImage
    }

    struct SnapshotKey: Hashable {
        let latitude: Double
        let longitude: Double
        let width: CGFloat
        let height: CGFloat
        let isDark: Bool
        let scale: CGFloat

        var cacheKey: NSString {
            String(
                format: "%.6f,%.6f,%.0fx%.0f@%.1f,%@",
                latitude, longitude, width, height, scale, isDark ? "dark" : "light"
            ) as NSString
        }
    }

    /// Nil when the snapshot fails (offline): the placeholder and marker stay.
    private static func render(_ key: SnapshotKey) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = region(around: CLLocationCoordinate2D(latitude: key.latitude, longitude: key.longitude))
        options.size = CGSize(width: key.width, height: key.height)
        options.traitCollection = traits(isDark: key.isDark, scale: key.scale)
        options.pointOfInterestFilter = .excludingAll

        // Not cancelled when the view goes: a cancelled snapshotter may never
        // call back, which would strand the continuation. One small image
        // finishing late is harmless; the caller drops it.
        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }
    }

    private static func traits(isDark: Bool, scale: CGFloat) -> UITraitCollection {
        let style: UIUserInterfaceStyle = isDark ? .dark : .light
        #if os(visionOS)
        return UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.displayScale = scale
        }
        #else
        if #available(iOS 17.0, *) {
            return UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.displayScale = scale
            }
        }
        return UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: scale),
        ])
        #endif
    }
}

struct InfoRow: View {
    var icon: String
    var title: LocalizedStringKey
    var value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.footnote)
                    .fontWeight(.light)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

/// Small uppercase heading above a group of rows. Shared across the station
/// screen's sections so they all sit on the same visual rhythm.
struct SectionLabel: View {
    var text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}
