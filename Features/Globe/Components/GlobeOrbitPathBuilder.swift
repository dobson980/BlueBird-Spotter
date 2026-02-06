//
//  GlobeOrbitPathBuilder.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import Foundation
import SatKit
import SceneKit
import UIKit
import simd

/// Builds orbit path data and SceneKit geometry for the globe renderer.
///
/// This utility isolates orbit-path generation from the coordinator, which keeps
/// UI orchestration and heavy math/geometry responsibilities separated.
enum GlobeOrbitPathBuilder {
    /// Chooses a lighter sample count when many paths are requested at once.
    nonisolated static func effectiveSampleCount(
        for mode: OrbitPathMode,
        desiredCount: Int,
        baseSampleCount: Int
    ) -> Int {
        guard mode == .all else { return baseSampleCount }
        if desiredCount > 150 {
            return max(40, baseSampleCount / 4)
        }
        if desiredCount > 60 {
            return max(60, baseSampleCount / 2)
        }
        return baseSampleCount
    }

    /// Computes orbit path vertices in scene space without touching actor-isolated state.
    nonisolated static func buildOrbitPathVertices(
        for satellite: Satellite,
        referenceDate: Date,
        sampleCount: Int,
        altitudeOffsetKm: Double
    ) -> [SIMD3<Float>] {
        guard sampleCount > 1,
              let meanMotion = parseMeanMotion(from: satellite.tleLine2),
              meanMotion > 0,
              let elements = try? SatKit.Elements(satellite.name, satellite.tleLine1, satellite.tleLine2) else {
            return []
        }

        let propagator = SatKit.selectPropagatorLegacy(elements)
        let epochDate = Date(ds1950: elements.t₀)
        let periodSeconds = 86400.0 / meanMotion
        let step = periodSeconds / Double(sampleCount)

        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(sampleCount + 1)

        for index in 0..<sampleCount {
            if Task.isCancelled { break }
            let date = referenceDate.addingTimeInterval(Double(index) * step)
            let minutesSinceEpoch = date.timeIntervalSince(epochDate) / 60.0
            guard let pvCoordinates = try? propagator.getPVCoordinates(minsAfterEpoch: minutesSinceEpoch) else {
                continue
            }

            let temePosition = SIMD3(
                pvCoordinates.position.x / 1000.0,
                pvCoordinates.position.y / 1000.0,
                pvCoordinates.position.z / 1000.0
            )
            let radiusKm = max(simd_length(temePosition), GlobeCoordinateConverter.earthRadiusKm)
            let adjustedRadius = max(GlobeCoordinateConverter.earthRadiusKm, radiusKm - altitudeOffsetKm)
            let normalized = temePosition / radiusKm
            let adjustedPosition = normalized * adjustedRadius

            let scale = GlobeCoordinateConverter.defaultScale
            // Map TEME axes to the scene axes used by GlobeCoordinateConverter:
            // TEME x -> scene z, TEME y -> scene x, TEME z -> scene y.
            vertices.append(
                SIMD3<Float>(
                    Float(adjustedPosition.y * scale),
                    Float(adjustedPosition.z * scale),
                    Float(adjustedPosition.x * scale)
                )
            )
        }

        // Close the loop so the orbit reads as one continuous path.
        if let first = vertices.first {
            vertices.append(first)
        }
        return vertices
    }

    /// Creates a SceneKit node for an orbital path line strip or ribbon.
    nonisolated static func makeOrbitPathNode(
        vertices: [SIMD3<Float>],
        config: OrbitPathConfig,
        categoryMask: Int
    ) -> SCNNode {
        let geometry = buildOrbitPathGeometry(vertices: vertices, config: config)
        let material = SCNMaterial()
        material.diffuse.contents = config.lineColor
        material.emission.contents = config.lineColor
        material.transparency = config.lineOpacity
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        // Orbit paths are visual-only; keep them out of satellite hit testing.
        node.categoryBitMask = categoryMask
        return node
    }

    /// Builds either a thin line or a ribbon geometry based on configured width.
    nonisolated private static func buildOrbitPathGeometry(vertices: [SIMD3<Float>], config: OrbitPathConfig) -> SCNGeometry {
        let lineWidth = Float(config.lineWidth)
        if lineWidth > 0.0005 {
            return buildOrbitRibbonGeometry(vertices: vertices, width: lineWidth)
        }
        return buildOrbitLineGeometry(vertices: vertices)
    }

    /// Builds a thin line geometry for the orbit path.
    nonisolated private static func buildOrbitLineGeometry(vertices: [SIMD3<Float>]) -> SCNGeometry {
        let scnVertices = vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: scnVertices)
        let indices = buildLineIndices(count: scnVertices.count)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        return SCNGeometry(sources: [source], elements: [element])
    }

    /// Builds a ribbon-style orbit path so thickness is visually adjustable.
    nonisolated private static func buildOrbitRibbonGeometry(vertices: [SIMD3<Float>], width: Float) -> SCNGeometry {
        guard vertices.count > 1 else {
            return buildOrbitLineGeometry(vertices: vertices)
        }

        let halfWidth = width * 0.5
        var ribbonVertices: [SCNVector3] = []
        ribbonVertices.reserveCapacity(vertices.count * 2)

        for index in vertices.indices {
            let current = vertices[index]
            let previous = index > 0 ? vertices[index - 1] : current
            let next = index + 1 < vertices.count ? vertices[index + 1] : current

            let tangentRaw = next - previous
            let tangentLength = simd_length(tangentRaw)
            let tangent = tangentLength > 0.0001
                ? (tangentRaw / tangentLength)
                : simd_float3(1, 0, 0)

            let radialRaw = current
            let radialLength = simd_length(radialRaw)
            let radial = radialLength > 0.0001
                ? (radialRaw / radialLength)
                : simd_float3(0, 1, 0)

            var side = simd_cross(tangent, radial)
            if simd_length(side) < 0.0001 {
                side = simd_cross(tangent, simd_float3(0, 1, 0))
            }
            if simd_length(side) < 0.0001 {
                side = simd_cross(radial, simd_float3(1, 0, 0))
            }
            side = simd_normalize(side)

            let offset = side * halfWidth
            let left = current + offset
            let right = current - offset
            ribbonVertices.append(SCNVector3(left.x, left.y, left.z))
            ribbonVertices.append(SCNVector3(right.x, right.y, right.z))
        }

        let indices = (0..<UInt32(ribbonVertices.count)).map { $0 }
        let source = SCNGeometrySource(vertices: ribbonVertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangleStrip)
        return SCNGeometry(sources: [source], elements: [element])
    }

    /// Builds the index list for consecutive line segments.
    nonisolated private static func buildLineIndices(count: Int) -> [UInt32] {
        guard count > 1 else { return [] }
        var indices: [UInt32] = []
        indices.reserveCapacity((count - 1) * 2)
        for index in 0..<(count - 1) {
            indices.append(UInt32(index))
            indices.append(UInt32(index + 1))
        }
        return indices
    }

    /// Extracts mean motion from TLE line 2.
    nonisolated private static func parseMeanMotion(from line: String) -> Double? {
        guard line.count >= 63 else { return nil }
        let start = line.index(line.startIndex, offsetBy: 52)
        let end = line.index(line.startIndex, offsetBy: 62)
        let substring = line[start...end].trimmingCharacters(in: .whitespaces)
        return Double(substring)
    }
}
