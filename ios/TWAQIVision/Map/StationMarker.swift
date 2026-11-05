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

/// Which badges win where stations crowd together: the worse the reading,
/// the stronger the claim to show its number.
struct BadgePriorityComponent: Component {
    let reading: Double
}

/// A pin standing on the island: its height is how far up the scale the
/// reading sits, and on top a 3D badge in the status colour carries the
/// number itself, always turned to face the reader. Where stations crowd, a
/// glowing dot stands in for the badge (see `MapScene.declutter`). In wind
/// mode the pin gives way to an arrow showing where the station's air is
/// heading.
enum StationMarker {
    struct Style {
        var index: AirIndexTypes
        var isWindMode: Bool
        var isFavourite: Bool
    }

    static let headRadius: Float = 0.0045
    static let headName = "head"
    static let badgeName = "badge"
    static let dotName = "dot"

    private static let badgeHeight: Float = 0.0105
    private static let badgeDepth: Float = 0.004
    private static let digitSize: CGFloat = 0.0074
    private static let digitDepth: Float = 0.0010
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

        // Everything visible hangs off one child, so the opening can grow it
        // while zoom keeps the marker itself a constant size.
        let body = Entity()
        body.name = bodyName
        marker.addChild(body)

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
            body.addChild(stem)

            // The badge sits clear of the stem's top; the dot, used when the
            // badge is crowded out, sits where the old pin head did.
            head = ModelEntity()
            head.position.y = stemHeight + badgeHeight / 2
            head.addChild(badge(
                text: value.format(f: style.index.getFormat()),
                color: color,
                textColor: UIColor(rgb: Int(status.getForegroundColor()))
            ))
            // No halo: in the crowds where dots appear, halos smear over the
            // badges behind them.
            let dot = glowingHead(color: color, radius: headRadius * 0.7, halo: false)
            dot.name = dotName
            dot.isEnabled = false
            head.addChild(dot)
            marker.components.set(BadgePriorityComponent(reading: value))
        }
        head.name = headName
        body.addChild(head)

        // A generous target: the head alone is too small to look at reliably.
        // A sphere, so it stays the same target however the badge turns.
        head.components.set(CollisionComponent(shapes: [.generateSphere(radius: headRadius * 2.4)]))
        head.components.set(InputTargetComponent())
        head.components.set(HoverEffectComponent())
        head.components.set(StationComponent(stationId: pollutant.stationId))

        if style.isFavourite {
            body.addChild(pinPlate())
        }
        return marker
    }

    static let bodyName = "body"

    /// Top of the marker's head, in `space`'s coordinates, for anchoring the card.
    static func headTop(of marker: Entity, in space: Entity) -> SIMD3<Float> {
        guard let head = marker.findEntity(named: headName) else { return marker.position(relativeTo: space) }
        let scale = marker.scale(relativeTo: space).y * head.scale.y
        return head.position(relativeTo: space) + SIMD3(0, max(headRadius, badgeHeight / 2) * scale, 0)
    }

    /// Shows the number, or only the dot when there's no room for it.
    @MainActor
    static func setShowsBadge(_ showsBadge: Bool, on marker: Entity) {
        marker.findEntity(named: badgeName)?.isEnabled = showsBadge
        marker.findEntity(named: dotName)?.isEnabled = !showsBadge
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

    /// A glossy pill in the status colour with the reading in raised digits
    /// on its face. `BillboardComponent` keeps the face turned to the reader
    /// as they walk round, or turn the map under it.
    @MainActor
    private static func badge(text: String, color: UIColor, textColor: UIColor) -> Entity {
        let badge = Entity()
        badge.name = badgeName
        badge.components.set(BillboardComponent())

        let digits = digitsMesh(text)
        let textWidth = digits.bounds.extents.x
        let width = max(badgeHeight * 1.5, textWidth + badgeHeight * 0.75)

        var shell = PhysicallyBasedMaterial()
        shell.baseColor = .init(tint: color)
        // Lit, so it reads as a solid object; partly emissive, so the status
        // colour still glows in a dim room.
        shell.emissiveColor = .init(color: color)
        shell.emissiveIntensity = 0.45
        shell.roughness = 0.35
        shell.clearcoat = 0.8
        shell.clearcoatRoughness = 0.15
        let pill = pillMesh(width: width)
        let shellEntity = ModelEntity(mesh: pill, materials: [shell])
        // Extrusion runs from z = 0; centre the pill on the badge.
        shellEntity.position = -pill.bounds.center
        badge.addChild(shellEntity)

        let number = ModelEntity(mesh: digits, materials: [UnlitMaterial(color: textColor)])
        // generateText starts at the baseline's left end; centre it on the
        // face, standing fully proud of it so the chamfer can't swallow it.
        let centre = digits.bounds.center
        number.position = SIMD3(-centre.x, -centre.y, badgeDepth / 2 - centre.z + digitDepth * 0.75)
        badge.addChild(number)
        return badge
    }

    @MainActor private static var digitMeshes: [String: MeshResource] = [:]
    @MainActor private static var pillMeshes: [Int: MeshResource] = [:]

    /// Cached: readings repeat across stations, and switching index rebuilds
    /// every marker.
    @MainActor
    private static func digitsMesh(_ text: String) -> MeshResource {
        if let cached = digitMeshes[text] { return cached }
        let font = UIFont.systemFont(ofSize: digitSize, weight: .heavy)
        let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: digitSize) } ?? font
        let mesh = MeshResource.generateText(text, extrusionDepth: digitDepth, font: rounded)
        digitMeshes[text] = mesh
        return mesh
    }

    /// A stadium extruded to `badgeDepth`, with softened edges. A rounded
    /// box can't do this: its corner radius is capped at half its thinnest
    /// side, which would leave a brick with chamfers.
    @MainActor
    private static func pillMesh(width: Float) -> MeshResource {
        // Quantised to a tenth of a millimetre, so similar widths share one mesh.
        let key = Int((width * 10_000).rounded())
        if let cached = pillMeshes[key] { return cached }
        let w = CGFloat(key) / 10_000, h = CGFloat(badgeHeight)
        let outline = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: h / 2)
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: badgeDepth)
        options.chamferRadius = badgeDepth * 0.25
        // The outline is a centimetre across; the default resolution, tuned
        // for larger shapes, would facet the rounded ends.
        options.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 12)
        let mesh = (try? MeshResource(extruding: outline, extrusionOptions: options))
            ?? .generateBox(width: Float(w), height: badgeHeight, depth: badgeDepth, cornerRadius: badgeDepth * 0.45)
        pillMeshes[key] = mesh
        return mesh
    }

    /// Unlit, so it reads as a light source whatever the room's lighting.
    @MainActor
    private static func glowingHead(color: UIColor, radius: Float, halo hasHalo: Bool = true) -> ModelEntity {
        let head = ModelEntity(mesh: .generateSphere(radius: radius), materials: [UnlitMaterial(color: color)])
        guard hasHalo else { return head }
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
