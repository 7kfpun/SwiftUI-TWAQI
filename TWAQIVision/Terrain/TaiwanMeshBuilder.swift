//
//  TaiwanMeshBuilder.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreGraphics
import RealityKit
import UIKit

/// Turns `TaiwanTerrain` into a diorama: a relief surface for the land, cut
/// out along the coast and extruded down like a carved block, standing in a
/// translucent sea.
enum TaiwanMeshBuilder {
    /// How far the carved block reaches below the waterline.
    static let baseDepth: Float = 0.012

    @MainActor
    static func makeIsland(_ terrain: TaiwanTerrain) async throws -> ModelEntity {
        // ~30k vertices and a 0.7-megapixel texture: keep it off the main actor.
        let (descriptors, image) = await Task.detached(priority: .userInitiated) {
            let geometry = Geometry(terrain)
            return ([geometry.surface(), geometry.sides()], reliefImage(terrain))
        }.value
        let mesh = try await MeshResource(from: descriptors)

        var surface = PhysicallyBasedMaterial()
        let texture = try await TextureResource(image: image, options: .init(semantic: .color))
        surface.baseColor = .init(texture: .init(texture))
        surface.roughness = 0.85
        surface.metallic = 0.0

        var sides = PhysicallyBasedMaterial()
        sides.baseColor = .init(tint: UIColor(red: 0.38, green: 0.34, blue: 0.30, alpha: 1))
        sides.roughness = 1.0

        let island = ModelEntity(mesh: mesh, materials: [surface, sides])
        island.name = "taiwan"
        return island
    }

    @MainActor
    static func makeSea(_ terrain: TaiwanTerrain) -> ModelEntity {
        let margin: Float = 0.02
        let mesh = MeshResource.generateBox(
            width: terrain.width + margin * 2, height: 0.001, depth: terrain.depth + margin * 2,
            cornerRadius: 0.0005
        )
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.10, green: 0.32, blue: 0.48, alpha: 1))
        material.roughness = 0.25
        material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        let sea = ModelEntity(mesh: mesh, materials: [material])
        sea.name = "sea"
        // Sits just under the coastal plain so the two never z-fight.
        sea.position.y = -0.0005
        return sea
    }

    // MARK: Geometry

    private struct Geometry {
        let terrain: TaiwanTerrain
        /// Top-surface vertex index per grid vertex, land only.
        private var vertexIndex: [Int: UInt32] = [:]
        private var positions: [SIMD3<Float>] = []
        private var normals: [SIMD3<Float>] = []
        private var uvs: [SIMD2<Float>] = []
        private var triangles: [UInt32] = []

        init(_ terrain: TaiwanTerrain) {
            self.terrain = terrain
            buildSurface()
        }

        func surface() -> MeshDescriptor {
            var descriptor = MeshDescriptor(name: "surface")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
            descriptor.primitives = .triangles(triangles)
            descriptor.materials = .allFaces(0)
            return descriptor
        }

        /// Walls along the coast plus a flat bottom, with their own flat normals.
        func sides() -> MeshDescriptor {
            var wallPositions: [SIMD3<Float>] = []
            var wallNormals: [SIMD3<Float>] = []
            var wallTriangles: [UInt32] = []
            let bottom = -baseDepth

            // An edge used by exactly one surface triangle is on the coast.
            // Each triangle is wound counter-clockwise seen from above, so its
            // edges run with the land on their left and the sea on the right.
            var edgeUse: [UInt64: Int] = [:]
            func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
                UInt64(min(a, b)) << 32 | UInt64(max(a, b))
            }
            for t in stride(from: 0, to: triangles.count, by: 3) {
                for e in 0..<3 {
                    edgeUse[key(triangles[t + e], triangles[t + (e + 1) % 3]), default: 0] += 1
                }
            }

            for t in stride(from: 0, to: triangles.count, by: 3) {
                for e in 0..<3 {
                    let a = triangles[t + e], b = triangles[t + (e + 1) % 3]
                    guard edgeUse[key(a, b)] == 1 else { continue }
                    let top0 = positions[Int(a)], top1 = positions[Int(b)]
                    let bottom0 = SIMD3(top0.x, bottom, top0.z), bottom1 = SIMD3(top1.x, bottom, top1.z)
                    let along = top1 - top0
                    // Outward: to the right of the edge, seen from above.
                    let outward = simd_normalize(SIMD3(-along.z, 0, along.x))

                    let base = UInt32(wallPositions.count)
                    wallPositions += [top0, top1, bottom1, bottom0]
                    wallNormals += Array(repeating: outward, count: 4)
                    wallTriangles += [base, base + 2, base + 1, base, base + 3, base + 2]
                }
            }

            // The underside, for anyone looking up through the sea.
            let base = UInt32(wallPositions.count)
            wallPositions += positions.map { SIMD3($0.x, bottom, $0.z) }
            wallNormals += Array(repeating: SIMD3(0, -1, 0), count: positions.count)
            for t in stride(from: 0, to: triangles.count, by: 3) {
                wallTriangles += [base + triangles[t], base + triangles[t + 2], base + triangles[t + 1]]
            }

            var descriptor = MeshDescriptor(name: "sides")
            descriptor.positions = MeshBuffers.Positions(wallPositions)
            descriptor.normals = MeshBuffers.Normals(wallNormals)
            descriptor.primitives = .triangles(wallTriangles)
            descriptor.materials = .allFaces(1)
            return descriptor
        }

        private mutating func buildSurface() {
            for row in 0..<terrain.rows {
                for column in 0..<terrain.columns where terrain.isLand(column: column, row: row) {
                    vertexIndex[row * terrain.columns + column] = UInt32(positions.count)
                    positions.append(terrain.position(column: column, row: row))
                    normals.append(normal(column: column, row: row))
                    uvs.append(SIMD2(
                        Float(column) / Float(terrain.columns - 1),
                        // Texture rows run top-down; UVs run bottom-up.
                        1 - Float(row) / Float(terrain.rows - 1)
                    ))
                }
            }

            // Each grid cell becomes two triangles when all four corners are
            // land, or one along the diagonal when three are, which cuts the
            // coast at 45° instead of in 1 km stair steps.
            for row in 0..<(terrain.rows - 1) {
                for column in 0..<(terrain.columns - 1) {
                    let nw = index(column, row), ne = index(column + 1, row)
                    let sw = index(column, row + 1), se = index(column + 1, row + 1)
                    switch (nw, ne, sw, se) {
                    case let (nw?, ne?, sw?, se?):
                        addTriangle(nw, sw, ne)
                        addTriangle(ne, sw, se)
                    case let (nil, ne?, sw?, se?): addTriangle(ne, sw, se)
                    case let (nw?, nil, sw?, se?): addTriangle(nw, sw, se)
                    case let (nw?, ne?, nil, se?): addTriangle(nw, se, ne)
                    case let (nw?, ne?, sw?, nil): addTriangle(nw, sw, ne)
                    default: break
                    }
                }
            }
        }

        private func index(_ column: Int, _ row: Int) -> UInt32? {
            vertexIndex[row * terrain.columns + column]
        }

        /// Appends a triangle wound counter-clockwise seen from above (+y),
        /// which RealityKit treats as front-facing.
        private mutating func addTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            let pa = positions[Int(a)], pb = positions[Int(b)], pc = positions[Int(c)]
            let up = simd_cross(pb - pa, pc - pa).y
            triangles += up >= 0 ? [a, b, c] : [a, c, b]
        }

        /// Central differences on the exaggerated surface, so lighting matches
        /// the relief the eye sees.
        private func normal(column: Int, row: Int) -> SIMD3<Float> {
            func height(_ c: Int, _ r: Int) -> Float {
                let clampedC = min(max(c, 0), terrain.columns - 1)
                let clampedR = min(max(r, 0), terrain.rows - 1)
                return terrain.surfaceY(column: clampedC, row: clampedR)
            }
            let dx = terrain.width / Float(terrain.columns - 1)
            let dz = terrain.depth / Float(terrain.rows - 1)
            let slopeX = (height(column + 1, row) - height(column - 1, row)) / (2 * dx)
            let slopeZ = (height(column, row + 1) - height(column, row - 1)) / (2 * dz)
            return simd_normalize(SIMD3(-slopeX, 1, -slopeZ))
        }
    }

    // MARK: Texture

    /// Hypsometric tint with a soft hillshade from the north-west, at twice
    /// the grid resolution. Kept muted so the AQI colours stay the loudest
    /// thing on the island.
    static func reliefImage(_ terrain: TaiwanTerrain, oversample: Int = 2) -> CGImage {
        let width = (terrain.columns - 1) * oversample + 1
        let height = (terrain.rows - 1) * oversample + 1
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        func metres(_ column: Double, _ row: Double) -> Double {
            let c0 = Int(column), r0 = Int(row)
            let fx = column - Double(c0), fy = row - Double(r0)
            func at(_ c: Int, _ r: Int) -> Double {
                Double(terrain.metres(column: min(c, terrain.columns - 1), row: min(r, terrain.rows - 1)) ?? 0)
            }
            let top = at(c0, r0) * (1 - fx) + at(c0 + 1, r0) * fx
            let bottom = at(c0, r0 + 1) * (1 - fx) + at(c0 + 1, r0 + 1) * fx
            return top * (1 - fy) + bottom * fy
        }

        // Ground spacing of one texel, in metres, with the same exaggeration as
        // the mesh so shading agrees with the geometry.
        let texelMetres = Double(terrain.depth / Float(terrain.rows - 1) / terrain.horizontalScale) * 1000
            / Double(oversample)
        let exaggeration = Double(terrain.verticalExaggeration)
        let light = simd_normalize(SIMD3<Double>(-1, 1.4, -1))

        for y in 0..<height {
            for x in 0..<width {
                let column = Double(x) / Double(oversample), row = Double(y) / Double(oversample)
                let elevation = metres(column, row)
                let step = 1 / Double(oversample)
                let east = metres(min(column + step, Double(terrain.columns - 1)), row)
                let west = metres(max(column - step, 0), row)
                let south = metres(column, min(row + step, Double(terrain.rows - 1)))
                let north = metres(column, max(row - step, 0))
                let normal = simd_normalize(SIMD3(
                    -(east - west) * exaggeration / (2 * texelMetres),
                    1,
                    -(south - north) * exaggeration / (2 * texelMetres)
                ))
                let shade = 0.72 + 0.4 * max(0, simd_dot(normal, light))
                let tint = hypsometric(elevation)
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(min(255, tint.x * shade * 255))
                pixels[offset + 1] = UInt8(min(255, tint.y * shade * 255))
                pixels[offset + 2] = UInt8(min(255, tint.z * shade * 255))
                pixels[offset + 3] = 255
            }
        }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }

    private static let ramp: [(metres: Double, color: SIMD3<Double>)] = [
        (0, SIMD3(0.56, 0.62, 0.52)),
        (400, SIMD3(0.64, 0.67, 0.55)),
        (1200, SIMD3(0.72, 0.69, 0.60)),
        (2400, SIMD3(0.80, 0.78, 0.74)),
        (3600, SIMD3(0.96, 0.96, 0.96)),
    ]

    private static func hypsometric(_ metres: Double) -> SIMD3<Double> {
        guard let upper = ramp.firstIndex(where: { $0.metres >= metres }) else { return ramp.last!.color }
        guard upper > 0 else { return ramp[0].color }
        let low = ramp[upper - 1], high = ramp[upper]
        let t = (metres - low.metres) / (high.metres - low.metres)
        return low.color + (high.color - low.color) * t
    }
}
