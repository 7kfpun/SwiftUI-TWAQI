//
//  StationMarker.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import RealityKit
import SwiftUI
import UIKit

/// Tags a marker with the station it stands for, so a tap can find it.
struct StationComponent: Component {
    let stationId: Int
}

/// A glowing pin standing on the island: the light's colour is the station's
/// air status, its height how far up the scale the reading sits. In wind mode
/// the pin gives way to an arrow showing where the station's air is heading.
enum StationMarker {
    struct Style {
        var index: AirIndexTypes
        var isWindMode: Bool
        var isFavourite: Bool
    }

    static let headRadius: Float = 0.0045
    private static let stemRadius: Float = 0.0006
    private static let minimumStem: Float = 0.008
    /// Added per colour band, so a hazardous station stands tallest.
    private static let stemPerBand: Float = 0.008

    /// Arrows float at one height so the flow reads as a single layer.
    private static let windHeight: Float = 0.014
    private static let shortestArrow: Float = 0.008
    private static let longestArrow: Float = 0.03

    @MainActor
    static func make(for pollutant: Pollutant, style: Style, terrain: TaiwanTerrain) -> Entity {
        let value = pollutant.getValue(airIndexType: style.index)
        let status = AirStatuses.checkAirStatus(airIndexType: style.index, value: value)
        let color = UIColor(rgb: Int(status.getColor()))

        let marker = Entity()
        marker.name = "station-\(pollutant.stationId)"
        marker.position = terrain.position(lat: pollutant.lat, lon: pollutant.lon)
        marker.components.set(StationComponent(stationId: pollutant.stationId))

        let head: ModelEntity
        if style.isWindMode {
            head = glowingHead(color: color, radius: headRadius * 0.6)
            head.position.y = windHeight
            if !pollutant.wind.isCalm {
                head.addChild(arrow(for: pollutant.wind, color: color))
            }
        } else {
            let stemHeight = minimumStem + stemPerBand * Float(bandPosition(value: value, index: style.index))
            let stem = ModelEntity(
                mesh: .generateCylinder(height: stemHeight, radius: stemRadius),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.7))]
            )
            stem.position.y = stemHeight / 2
            marker.addChild(stem)

            head = glowingHead(color: color, radius: headRadius)
            head.position.y = stemHeight + headRadius
        }
        head.name = "head"
        marker.addChild(head)

        // A generous target: the head alone is too small to look at reliably.
        head.components.set(CollisionComponent(shapes: [.generateSphere(radius: headRadius * 2.2)]))
        head.components.set(InputTargetComponent())
        head.components.set(HoverEffectComponent())
        head.components.set(StationComponent(stationId: pollutant.stationId))

        if style.isFavourite {
            marker.addChild(pinPlate())
        }
        return marker
    }

    /// Height of the marker's head above its station, for anchoring the card.
    static func headTop(of marker: Entity) -> SIMD3<Float> {
        let head = marker.findEntity(named: "head")
        return marker.position + (head?.position ?? .zero) + SIMD3(0, headRadius, 0)
    }

    /// `0` for no reading, then `1…6` across the bands, fractional within one.
    static func bandPosition(value: Double, index: AirIndexTypes) -> Double {
        guard let bands = AirStatuses.bands[index],
              let position = bands.firstIndex(where: { $0.range.contains(value) })
        else { return 0 }
        let range = bands[position].range
        // The top band is open-ended; don't let one outlier tower over the rest.
        let fraction = position == bands.count - 1
            ? 0.5
            : (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return Double(position) + 1 + min(max(fraction, 0), 1) - 0.5
    }

    // MARK: Parts

    /// Unlit, so it reads as a light source whatever the room's lighting.
    @MainActor
    private static func glowingHead(color: UIColor, radius: Float) -> ModelEntity {
        let head = ModelEntity(mesh: .generateSphere(radius: radius), materials: [UnlitMaterial(color: color)])
        var halo = UnlitMaterial(color: color)
        halo.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        head.addChild(ModelEntity(mesh: .generateSphere(radius: radius * 1.9), materials: [halo]))
        return head
    }

    /// Points downwind, longer in a stronger wind, like the iOS flow field.
    @MainActor
    private static func arrow(for wind: Wind, color: UIColor) -> Entity {
        let length = shortestArrow + (longestArrow - shortestArrow) * Float(wind.strengthFraction)
        let tipLength: Float = 0.005
        let material = UnlitMaterial(color: color.withAlphaComponent(0.9))
        // Built pointing north (-z): the parts are y-up meshes tipped forward.
        let tipForward = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        let shaft = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.0008), materials: [material])
        shaft.orientation = tipForward
        shaft.position.z = -length / 2

        let tip = ModelEntity(mesh: .generateCone(height: tipLength, radius: 0.0024), materials: [material])
        tip.orientation = tipForward
        tip.position.z = -length - tipLength / 2

        let arrow = Entity()
        arrow.addChild(shaft)
        arrow.addChild(tip)
        // The API's bearing is where the wind comes *from*, clockwise from
        // north; the arrow shows where it's going.
        let downwind = Float((wind.direction + 180) * .pi / 180)
        arrow.orientation = simd_quatf(angle: -downwind, axis: [0, 1, 0])
        return arrow
    }

    /// A white disc at the foot of a favourite or pinned station.
    @MainActor
    private static func pinPlate() -> Entity {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        let plate = ModelEntity(mesh: .generateCylinder(height: 0.0008, radius: 0.0065), materials: [material])
        plate.position.y = 0.0006
        return plate
    }
}
