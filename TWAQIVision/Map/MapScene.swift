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
    /// Everything that spins together when the reader turns the map.
    private let turntable = Entity()
    private let markers = Entity()
    private var card: Entity?
    private(set) var terrain: TaiwanTerrain?

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

    init() {
        root.addChild(turntable)
        turntable.addChild(markers)
        userBeacon.isEnabled = false
        turntable.addChild(userBeacon)
    }

    func load(layout: MapLayout) async throws {
        root.position = layout.origin
        let terrain = try TaiwanTerrain(fittingDepth: layout.mapDepth)
        self.terrain = terrain

        let sea = TaiwanMeshBuilder.makeSea(terrain)
        // Thick enough to catch a pinch anywhere over the map, island included.
        sea.components.set(CollisionComponent(shapes: [
            .generateBox(width: terrain.width, height: 0.01, depth: terrain.depth),
        ]))
        sea.components.set(InputTargetComponent())
        turntable.addChild(sea)
        turntable.addChild(try await TaiwanMeshBuilder.makeIsland(terrain))
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
        }

        placeUserBeacon(at: userLocation, on: terrain)

        guard selectedStationId != appliedSelection || card?.isEnabled != (selectedStationId != nil) else { return }
        appliedSelection = selectedStationId
        for marker in markers.children {
            let isSelected = marker.components[StationComponent.self]?.stationId == selectedStationId
            marker.findEntity(named: "head")?.scale = SIMD3(repeating: isSelected ? 1.6 : 1)
        }

        guard let card else { return }
        guard let id = selectedStationId, let marker = markers.findEntity(named: "station-\(id)") else {
            card.isEnabled = false
            return
        }
        // Attachments are centred on their entity; lift by half the card so
        // its bottom edge floats just over the pin.
        let halfHeight = card.visualBounds(relativeTo: card).extents.y / 2
        card.position = StationMarker.headTop(of: marker) + SIMD3(0, 0.015 + halfHeight, 0)
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
