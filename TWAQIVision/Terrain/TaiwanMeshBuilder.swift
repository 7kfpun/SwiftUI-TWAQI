//
//  TaiwanMeshBuilder.swift
//  TWAQIVision
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import RealityKit
import UIKit

/// Turns `TaiwanTerrain` into a diorama: a round base of ocean shaded by depth, with
/// the island's relief rising out of it, cut along the coast like a carved
/// block. Both are painted with the one texture baked alongside the terrain,
/// `TaiwanRelief.png`, so land and sea meet exactly.
enum TaiwanMeshBuilder {
    /// How far the carved island reaches below the waterline.
    static let baseDepth: Float = 0.012
    /// The ocean base's thickness: deeper than the island's base, so the two
    /// bottoms never share a plane.
    static let oceanDepth: Float = 0.016
    /// The sea surface sits just under the coastal plain so they never z-fight.
    static let seaLevel: Float = -0.0005

    enum LoadError: Error {
        case missingTexture
    }

    struct Diorama {
        let island: ModelEntity
        let ocean: ModelEntity
    }

    @MainActor
    static func makeDiorama(_ terrain: TaiwanTerrain, bundle: Bundle = .main) async throws -> Diorama {
        guard let textureURL = bundle.url(forResource: "TaiwanRelief", withExtension: "png") else {
            throw LoadError.missingTexture
        }
        // ~30k vertices: built off the main actor.
        let islandDescriptors = await Task.detached(priority: .userInitiated) {
            let geometry = Geometry(terrain)
            return [geometry.surface(), geometry.sides()]
        }.value
        let islandMesh = try await MeshResource(from: islandDescriptors)
        let oceanMesh = try await MeshResource(from: Ocean(terrain).descriptors())
        let texture = try await TextureResource(contentsOf: textureURL, options: .init(semantic: .color))

        var land = PhysicallyBasedMaterial()
        land.baseColor = .init(texture: .init(texture))
        land.roughness = 0.85
        land.metallic = 0.0

        var cliffs = PhysicallyBasedMaterial()
        cliffs.baseColor = .init(tint: UIColor(red: 0.38, green: 0.34, blue: 0.30, alpha: 1))
        cliffs.roughness = 1.0

        // Smooth, with a clear coat, so the room's light glints off the water.
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(texture: .init(texture))
        water.roughness = 0.35
        water.clearcoat = 0.6
        water.clearcoatRoughness = 0.1

        var depths = PhysicallyBasedMaterial()
        depths.baseColor = .init(tint: UIColor(red: 0.04, green: 0.14, blue: 0.30, alpha: 1))
        depths.roughness = 0.6

        let island = ModelEntity(mesh: islandMesh, materials: [land, cliffs])
        island.name = "taiwan"
        let ocean = ModelEntity(mesh: oceanMesh, materials: [water, depths])
        ocean.name = "sea"
        return Diorama(island: island, ocean: ocean)
    }

    // MARK: Ocean

    /// The round base the island stands in: a disc of sea textured with the
    /// same UVs as the island, a curved side and a flat bottom.
    private struct Ocean {
        let top: Float = seaLevel
        let bottom: Float = -oceanDepth
        let radius: Float
        let halfWidth: Float
        let halfDepth: Float
        /// Enough that the rim reads as a circle, not a polygon, at arm's length.
        let segments = 160

        init(_ terrain: TaiwanTerrain) {
            radius = terrain.discRadius
            halfWidth = terrain.width / 2
            halfDepth = terrain.depth / 2
        }

        /// Point on the rim, angle measured clockwise seen from above.
        private func rim(_ i: Int) -> SIMD2<Float> {
            let angle = Float(i) / Float(segments) * 2 * .pi
            return SIMD2(radius * cos(angle), radius * sin(angle))
        }

        /// Same convention as the island: u east, v north.
        private func uv(_ point: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2((point.x + halfWidth) / (2 * halfWidth), 1 - (point.y + halfDepth) / (2 * halfDepth))
        }

        func descriptors() -> [MeshDescriptor] {
            // Top: a fan around the centre. Rim points run with +x towards +z,
            // clockwise from above, so each triangle is (centre, next, this) to
            // face up.
            var topPositions: [SIMD3<Float>] = [[0, top, 0]]
            var topUVs: [SIMD2<Float>] = [uv(.zero)]
            for i in 0..<segments {
                let point = rim(i)
                topPositions.append([point.x, top, point.y])
                topUVs.append(uv(point))
            }
            var topTriangles: [UInt32] = []
            for i in 0..<segments {
                let this = UInt32(1 + i), next = UInt32(1 + (i + 1) % segments)
                topTriangles += [0, next, this]
            }
            var surface = MeshDescriptor(name: "ocean-surface")
            surface.positions = MeshBuffers.Positions(topPositions)
            surface.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: topPositions.count))
            surface.textureCoordinates = MeshBuffers.TextureCoordinates(topUVs)
            surface.primitives = .triangles(topTriangles)
            surface.materials = .allFaces(0)

            // Side: smooth outward normals so the rim catches light like a
            // turned edge; then the bottom, facing down.
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var triangles: [UInt32] = []
            for i in 0..<segments {
                let point = rim(i)
                let outward = simd_normalize(SIMD3(point.x, 0, point.y))
                positions += [[point.x, top, point.y], [point.x, bottom, point.y]]
                normals += [outward, outward]
            }
            for i in 0..<segments {
                let a = UInt32(2 * i), b = UInt32(2 * ((i + 1) % segments))
                // a/b top, a+1/b+1 bottom; wound to face outward.
                triangles += [a, b, a + 1, b, b + 1, a + 1]
            }
            let centre = UInt32(positions.count)
            positions.append([0, bottom, 0])
            normals.append([0, -1, 0])
            for i in 0..<segments {
                let point = rim(i)
                positions.append([point.x, bottom, point.y])
                normals.append([0, -1, 0])
            }
            for i in 0..<segments {
                let this = centre + 1 + UInt32(i), next = centre + 1 + UInt32((i + 1) % segments)
                triangles += [centre, this, next]
            }

            var sides = MeshDescriptor(name: "ocean-sides")
            sides.positions = MeshBuffers.Positions(positions)
            sides.normals = MeshBuffers.Normals(normals)
            sides.primitives = .triangles(triangles)
            sides.materials = .allFaces(1)
            return [surface, sides]
        }
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
}
