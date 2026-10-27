//
//  MapScene.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import RealityKit
import SwiftUI

/// Where the diorama sits and how big it is, per presentation.
enum MapLayout {
    /// Inside the app's volumetric window.
    case volume
    /// Life-size-ish on a virtual table in the immersive space.
    case tabletop

    /// North–south size of the model, Matsu to Orchid Island.
    var mapDepth: Float {
        switch self {
        case .volume: return 0.8
        // Bigger than the volume, but small enough to take in at a glance.
        case .tabletop: return 1.1
        }
    }

    var origin: SIMD3<Float> {
        switch self {
        // A volume's origin is its centre; stand the map near the floor of it.
        case .volume: return [0, -VolumeSize.height / 2 + 0.03, 0]
        // An immersive space's origin is the floor under the viewer. Far
        // enough out that the whole island sits below eye level in view,
        // rather than its centre falling out of the bottom of it.
        case .tabletop: return [0, 1.0, -1.9]
        }
    }
}

enum VolumeSize {
    static let width: Float = 0.9
    static let height: Float = 0.45
    static let depth: Float = 0.9
}

/// Owns the RealityKit side of the map so SwiftUI updates can be diffed
/// instead of rebuilding the island on every state change.
@MainActor
final class MapScene {
    let root = Entity()
    /// Everything that turns and zooms together when the reader moves the map.
    private let turntable = Entity()
    /// The ocean and the island, which the opening brings in together.
    private let diorama = Entity()
    private let markers = Entity()
    private var card: Entity?
    private(set) var terrain: TaiwanTerrain?

    /// Finishes when the opening has played, so the pins wait for the island.
    private var opening: Task<Void, Never>?
    private var hasRevealedPins = false
    private var reduceMotion = false

    private struct MarkerState: Equatable {
        let stations: Pollutants
        let index: AirIndexTypes
        let isWindMode: Bool
        let favourites: Set<Int>
    }
    private var appliedMarkers: MarkerState?
    private var appliedSelection: Int?
    private let userBeacon = MapScene.makeUserBeacon()

    private var dragStartYaw: Float?
    private var yaw: Float = 0

    private var zoom: Float = 1
    private var zoomStart: (scale: Float, offset: SIMD3<Float>)?
    /// Further in, the island spills well past a volume and stations crowd
    /// the view rather than separating.
    private static let maxZoom: Float = 3

    init() {
        root.addChild(turntable)
        turntable.addChild(diorama)
        turntable.addChild(markers)
        userBeacon.isEnabled = false
        turntable.addChild(userBeacon)
    }

    func load(layout: MapLayout, reduceMotion: Bool) async throws {
        self.reduceMotion = reduceMotion
        root.position = layout.origin
        let terrain = try TaiwanTerrain(fittingDepth: layout.mapDepth)
        self.terrain = terrain

        let model = try await TaiwanMeshBuilder.makeDiorama(terrain)
        // Thick enough to catch a pinch anywhere over the map, island included.
        model.ocean.components.set(CollisionComponent(shapes: [
            .generateBox(width: terrain.width, height: 0.01, depth: terrain.depth),
        ]))
        model.ocean.components.set(InputTargetComponent())
        diorama.addChild(model.ocean)
        diorama.addChild(model.island)
        playOpening(island: model.island)
    }

    // MARK: Opening

    /// The map arrives as a flat chart that turns into place, then the
    /// mountains rise out of it, then the stations light up north to south.
    private func playOpening(island: Entity) {
        guard !reduceMotion else { return }

        diorama.components.set(OpacityComponent(opacity: 0))
        let fade = FromToByAnimation<Float>(
            from: 0, to: 1, duration: 0.9, timing: .easeOut, bindTarget: .opacity
        )
        if let resource = try? AnimationResource.generate(with: fade) {
            diorama.playAnimation(resource)
        }
        diorama.transform = Transform(
            scale: SIMD3(repeating: 0.92),
            rotation: simd_quatf(angle: -0.35, axis: [0, 1, 0]),
            translation: [0, -0.015, 0]
        )
        diorama.move(to: Transform.identity, relativeTo: turntable, duration: 1.4, timingFunction: .easeOut)

        island.scale = [1, 0.02, 1]
        opening = Task { [diorama] in
            try? await Task.sleep(for: .seconds(0.6))
            island.move(
                to: Transform(scale: .one, rotation: island.orientation, translation: island.position),
                relativeTo: island.parent, duration: 1.6, timingFunction: .easeInOut
            )
            try? await Task.sleep(for: .seconds(1.2))
            // Done fading: left in place, it would keep the whole map in
            // the transparent pass.
            diorama.components.remove(OpacityComponent.self)
        }
    }

    /// Pins grow out of the island in a wave from Matsu to Orchid Island,
    /// once the island is up. Only the first time readings arrive.
    private func revealPins() {
        guard !hasRevealedPins, !markers.children.isEmpty else { return }
        hasRevealedPins = true
        guard !reduceMotion else { return }

        let bodies = markers.children.compactMap { marker in
            marker.findEntity(named: StationMarker.bodyName).map { (body: $0, z: marker.position.z) }
        }
        bodies.forEach { $0.body.scale = [1, 0.001, 1] }
        let north = bodies.map(\.z).min() ?? 0, south = bodies.map(\.z).max() ?? 1
        let span = max(south - north, 0.001)

        Task { [opening] in
            await opening?.value
            for (body, z) in bodies.sorted(by: { $0.z < $1.z }) {
                let delay = Double((z - north) / span) * 1.1
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    body.move(
                        to: Transform(scale: .one, rotation: body.orientation, translation: body.position),
                        relativeTo: body.parent, duration: 0.45, timingFunction: .easeOut
                    )
                }
            }
        }
    }

    func attachCard(_ entity: Entity) {
        entity.components.set(BillboardComponent())
        entity.isEnabled = false
        turntable.addChild(entity)
        card = entity
    }

    func apply(
        stations: Pollutants, index: AirIndexTypes, isWindMode: Bool, favourites: [Int],
        userLocation: CLLocation?, selectedStationId: Int?
    ) {
        guard let terrain else { return }

        let state = MarkerState(stations: stations, index: index, isWindMode: isWindMode, favourites: Set(favourites))
        if state != appliedMarkers {
            markers.children.removeAll()
            for station in stations {
                let style = StationMarker.Style(
                    index: index, isWindMode: isWindMode, isFavourite: state.favourites.contains(station.stationId)
                )
                markers.addChild(StationMarker.make(for: station, style: style, terrain: terrain))
            }
            appliedMarkers = state
            appliedSelection = nil
            keepMarkersLifeSize()
            revealPins()
        }

        placeUserBeacon(at: userLocation, on: terrain)

        guard selectedStationId != appliedSelection || card?.isEnabled != (selectedStationId != nil) else { return }
        appliedSelection = selectedStationId
        for marker in markers.children {
            let isSelected = marker.components[StationComponent.self]?.stationId == selectedStationId
            marker.findEntity(named: StationMarker.headName)?.scale = SIMD3(repeating: isSelected ? 1.3 : 1)
        }
        declutter()

        placeCard()
    }

    private func placeCard() {
        guard let card else { return }
        guard let id = appliedSelection, let marker = markers.findEntity(named: "station-\(id)") else {
            card.isEnabled = false
            return
        }
        // Attachments are centred on their entity; lift by half the card so
        // its bottom edge floats just over the pin. Counter-scaled like the
        // pins, so zooming doesn't blow the card up.
        let lifeSize = 1 / zoom
        card.scale = SIMD3(repeating: lifeSize)
        let halfHeight = card.visualBounds(relativeTo: card).extents.y / 2
        card.position = StationMarker.headTop(of: marker, in: turntable) + SIMD3(0, (0.015 + halfHeight) * lifeSize, 0)
        card.isEnabled = true
    }

    // MARK: You are here

    /// Only shown inside the map: a reader abroad has nowhere on it to stand.
    private func placeUserBeacon(at location: CLLocation?, on terrain: TaiwanTerrain) {
        guard let coordinate = location?.coordinate,
              (terrain.minLat...terrain.maxLat).contains(coordinate.latitude),
              (terrain.minLon...terrain.maxLon).contains(coordinate.longitude)
        else {
            userBeacon.isEnabled = false
            return
        }
        userBeacon.position = terrain.position(lat: coordinate.latitude, lon: coordinate.longitude)
        userBeacon.isEnabled = true
    }

    /// A blue light with a faint column above it, in the system's location colour.
    private static func makeUserBeacon() -> Entity {
        let blue = UIColor.systemBlue
        let beacon = Entity()
        beacon.name = "you-are-here"

        let dot = ModelEntity(mesh: .generateSphere(radius: 0.003), materials: [UnlitMaterial(color: blue)])
        dot.position.y = 0.003
        beacon.addChild(dot)

        let beamHeight: Float = 0.08
        var beamMaterial = UnlitMaterial(color: blue)
        beamMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.25))
        let beam = ModelEntity(mesh: .generateCylinder(height: beamHeight, radius: 0.0012), materials: [beamMaterial])
        beam.position.y = beamHeight / 2
        beacon.addChild(beam)
        return beacon
    }

    // MARK: Zooming

    /// Two-handed pinch. The point between the hands stays put while the map
    /// grows or shrinks around it, so zooming is also how you move in on a
    /// region. `anchor` is in `root`'s space.
    func magnify(by magnification: Double, around anchor: SIMD3<Float>) {
        guard let terrain else { return }
        let start = zoomStart ?? (scale: zoom, offset: turntable.position)
        zoomStart = start

        let scale = min(max(start.scale * Float(magnification), 1), Self.maxZoom)
        var offset = anchor - (scale / start.scale) * (anchor - start.offset)
        offset.y = 0
        // Never let the island slide out from under the view entirely.
        let slackX = (scale - 1) * terrain.width / 2, slackZ = (scale - 1) * terrain.depth / 2
        offset.x = min(max(offset.x, -slackX), slackX)
        offset.z = min(max(offset.z, -slackZ), slackZ)

        zoom = scale
        turntable.scale = SIMD3(repeating: scale)
        turntable.position = offset
        keepMarkersLifeSize()
        placeCard()
    }

    func endMagnify() {
        zoomStart = nil
    }

    /// The terrain grows when zoomed; the pins, the you-are-here beacon and
    /// the card stay the size they were, so they spread apart instead of
    /// swelling into each other.
    private func keepMarkersLifeSize() {
        let lifeSize = SIMD3<Float>(repeating: 1 / zoom)
        for marker in markers.children {
            marker.scale = lifeSize
        }
        userBeacon.scale = lifeSize
        declutter()
    }

    // MARK: Crowding

    /// Badges are a fixed size but the map isn't, so around Taipei a badge
    /// per station would stack into an unreadable pile. Worst readings claim
    /// space first; a station with no room left shows a glowing dot instead.
    /// Zooming in spreads stations apart, so more of them get their number.
    private func declutter() {
        // Closest two badge centres may sit, in metres as seen. Wider than a
        // badge: the map is viewed at a slant, so stations one behind the
        // other overlap on screen well before they meet on the map.
        let spacing: Float = 0.034 / zoom
        let candidates = markers.children
            .compactMap { marker -> (marker: Entity, reading: Double, isSelected: Bool)? in
                guard let priority = marker.components[BadgePriorityComponent.self] else { return nil }
                let isSelected = marker.components[StationComponent.self]?.stationId == appliedSelection
                return (marker, priority.reading, isSelected)
            }
            // The selected station first, so its number is never hidden.
            .sorted { ($0.isSelected ? 1 : 0, $0.reading) > ($1.isSelected ? 1 : 0, $1.reading) }

        var placed: [SIMD2<Float>] = []
        for candidate in candidates {
            let position = SIMD2(candidate.marker.position.x, candidate.marker.position.z)
            let hasRoom = placed.allSatisfy { simd_distance($0, position) >= spacing }
            if hasRoom {
                placed.append(position)
            }
            StationMarker.setShowsBadge(hasRoom, on: candidate.marker)
        }
    }

    // MARK: Turning

    func rotate(by translation: CGSize) {
        let start = dragStartYaw ?? yaw
        dragStartYaw = start
        // Drag right to turn the island clockwise, seen from above.
        yaw = start + Float(translation.width) / 300
        turntable.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    func endRotation() {
        dragStartYaw = nil
    }

    static func stationId(for entity: Entity) -> Int? {
        var current: Entity? = entity
        while let candidate = current {
            if let station = candidate.components[StationComponent.self] { return station.stationId }
            current = candidate.parent
        }
        return nil
    }
}
