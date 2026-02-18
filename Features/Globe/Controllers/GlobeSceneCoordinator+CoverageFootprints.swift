//
//  GlobeSceneCoordinator+CoverageFootprints.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/17/26.
//

import QuartzCore
import SceneKit
import simd
import UIKit

/// Coverage-footprint rendering for the globe scene.
///
/// This overlay is intentionally educational. It uses geometry-only estimates
/// so users can compare relative service regions, not exact RF performance.
extension GlobeSceneCoordinator {
    /// Visual tuning constants for the semi-transparent coverage overlays.
    private enum CoverageVisuals {
        /// Slight offset prevents z-fighting against the Earth mesh.
        static let surfaceOffsetScene: Float = 0.004
        /// Radial subdivision count for the spherical cap mesh.
        static let radialSegments = 16
        /// Angular subdivision count for the spherical cap mesh.
        static let angularSegments = 96
        /// Base fill color used for coverage overlays.
        static let fillColor = UIColor(red: 0.11, green: 0.76, blue: 0.95, alpha: 1.0)
        /// Opacity that keeps Earth detail visible through the overlay.
        static let fillOpacity: CGFloat = 0.28
        /// Quantization scale for geometry caching.
        static let angleQuantizationScale: Double = 2_000
    }

    /// Updates coverage overlays for the tracked satellites.
    func updateCoverageFootprints(
        for tracked: [TrackedSatellite],
        selectedId: Int?,
        mode: CoverageFootprintMode,
        in scene: SCNScene,
        animationDuration: TimeInterval
    ) {
        let visibleSatelliteIDs: Set<Int>
        switch mode {
        case .off:
            visibleSatelliteIDs = []
        case .selectedOnly:
            if let selectedId {
                visibleSatelliteIDs = [selectedId]
            } else {
                visibleSatelliteIDs = []
            }
        case .all:
            visibleSatelliteIDs = Set(tracked.map { $0.satellite.id })
        }

        guard !visibleSatelliteIDs.isEmpty else {
            clearCoverageFootprints()
            return
        }

        for satelliteId in coverageNodes.keys where !visibleSatelliteIDs.contains(satelliteId) {
            removeCoverageNode(for: satelliteId)
        }

        var orientationUpdates: [(node: SCNNode, orientation: simd_quatf)] = []
        orientationUpdates.reserveCapacity(tracked.count)

        for trackedSatellite in tracked {
            let satelliteId = trackedSatellite.satellite.id
            guard visibleSatelliteIDs.contains(satelliteId) else {
                removeCoverageNode(for: satelliteId)
                continue
            }

            guard let halfAngleRadians = coverageHalfAngleRadians(for: trackedSatellite) else {
                removeCoverageNode(for: satelliteId)
                continue
            }

            let subSatellitePoint = GlobeCoordinateConverter.scenePosition(
                latitudeDegrees: trackedSatellite.position.latitudeDegrees,
                longitudeDegrees: trackedSatellite.position.longitudeDegrees,
                altitudeKm: 0
            )
            let direction = simd_float3(
                Float(subSatellitePoint.x),
                Float(subSatellitePoint.y),
                Float(subSatellitePoint.z)
            )
            let directionLength = simd_length(direction)
            guard directionLength > 0 else { continue }
            let orientation = orientationAligningPositiveZ(to: direction / directionLength)

            let geometryKey = quantizedCoverageKey(for: halfAngleRadians)
            let isExistingNode = coverageNodes[satelliteId] != nil
            let node = coverageNodes[satelliteId] ?? makeCoverageNode(
                for: satelliteId,
                geometry: coverageGeometry(for: halfAngleRadians, key: geometryKey)
            )
            if !isExistingNode {
                // New nodes should appear directly under the selected satellite footprint.
                // If we animate from identity orientation, the cap can look like it "slides"
                // across the planet once before settling into place.
                node.simdOrientation = orientation
                scene.rootNode.addChildNode(node)
                coverageNodes[satelliteId] = node
            }

            if coverageGeometryKeys[satelliteId] != geometryKey {
                node.geometry = coverageGeometry(for: halfAngleRadians, key: geometryKey)
                coverageGeometryKeys[satelliteId] = geometryKey
            }

            if isExistingNode {
                orientationUpdates.append((node: node, orientation: orientation))
            }
        }

        // Matching the satellite interpolation duration keeps overlays moving smoothly.
        SCNTransaction.begin()
        SCNTransaction.disableActions = animationDuration == 0
        SCNTransaction.animationDuration = animationDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        for update in orientationUpdates {
            update.node.simdOrientation = update.orientation
        }
        SCNTransaction.commit()
    }

    /// Creates one reusable coverage node for a satellite id.
    private func makeCoverageNode(for satelliteId: Int, geometry: SCNGeometry) -> SCNNode {
        let node = SCNNode(geometry: geometry)
        node.name = "coverage-\(satelliteId)"
        node.position = SCNVector3Zero
        node.renderingOrder = 5
        node.categoryBitMask = GlobeSceneView.coverageCategoryMask
        return node
    }

    /// Removes all coverage overlays from the scene graph.
    private func clearCoverageFootprints() {
        for node in coverageNodes.values {
            node.removeFromParentNode()
        }
        coverageNodes.removeAll()
        coverageGeometryKeys.removeAll()
    }

    /// Removes one coverage node when a satellite disappears or has invalid input.
    private func removeCoverageNode(for satelliteId: Int) {
        coverageNodes[satelliteId]?.removeFromParentNode()
        coverageNodes[satelliteId] = nil
        coverageGeometryKeys[satelliteId] = nil
    }

    /// Returns a cached spherical-cap geometry for a quantized footprint angle.
    private func coverageGeometry(for halfAngleRadians: Double, key: Int) -> SCNGeometry {
        if let cached = coverageGeometryCache[key] {
            return cached
        }

        let geometry = buildCoverageGeometry(halfAngleRadians: Float(halfAngleRadians))
        coverageGeometryCache[key] = geometry
        return geometry
    }

    /// Quantizes footprint angles so nearby values share the same mesh cache entry.
    private func quantizedCoverageKey(for halfAngleRadians: Double) -> Int {
        Int((halfAngleRadians * CoverageVisuals.angleQuantizationScale).rounded())
    }

    /// Builds a spherical-cap mesh centered on +Z, then rotated per satellite.
    private func buildCoverageGeometry(halfAngleRadians: Float) -> SCNGeometry {
        let radialSegments = CoverageVisuals.radialSegments
        let angularSegments = CoverageVisuals.angularSegments
        let radius = GlobeSceneView.earthRadiusScene + CoverageVisuals.surfaceOffsetScene
        let ringCount = angularSegments + 1

        var vertices: [SCNVector3] = []
        vertices.reserveCapacity((radialSegments + 1) * ringCount)

        for radialStep in 0...radialSegments {
            let progress = Float(radialStep) / Float(radialSegments)
            let centralAngle = halfAngleRadians * progress
            let ringRadius = radius * sin(centralAngle)
            let z = radius * cos(centralAngle)

            for angleStep in 0...angularSegments {
                let azimuth = (Float(angleStep) / Float(angularSegments)) * (2 * Float.pi)
                let x = ringRadius * cos(azimuth)
                let y = ringRadius * sin(azimuth)
                vertices.append(SCNVector3(x, y, z))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(radialSegments * angularSegments * 6)
        for radialStep in 0..<radialSegments {
            let base = radialStep * ringCount
            let nextBase = (radialStep + 1) * ringCount
            for angleStep in 0..<angularSegments {
                let a = UInt32(base + angleStep)
                let b = UInt32(base + angleStep + 1)
                let c = UInt32(nextBase + angleStep)
                let d = UInt32(nextBase + angleStep + 1)
                indices.append(a)
                indices.append(c)
                indices.append(b)
                indices.append(b)
                indices.append(c)
                indices.append(d)
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        geometry.materials = [coverageMaterial()]
        return geometry
    }

    /// Builds a translucent material so Earth remains visible under the overlay.
    private func coverageMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = CoverageVisuals.fillColor
        material.emission.contents = CoverageVisuals.fillColor
        material.emission.intensity = 0.08
        material.transparency = CoverageVisuals.fillOpacity
        material.lightingModel = .lambert
        material.isDoubleSided = false
        material.cullMode = .back
        material.blendMode = .alpha
        material.transparencyMode = .singleLayer
        material.readsFromDepthBuffer = true
        // Do not write depth for transparent overlays. This avoids self-occlusion
        // artifacts where parts of the footprint can look visibly "cut off."
        material.writesToDepthBuffer = false
        return material
    }

    /// Computes the shortest rotation that maps +Z onto a target direction.
    private func orientationAligningPositiveZ(to direction: simd_float3) -> simd_quatf {
        let from = simd_float3(0, 0, 1)
        let dot = simd_dot(from, direction)

        if dot > 0.9999 {
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        if dot < -0.9999 {
            // 180° around Y flips +Z to -Z.
            return simd_quatf(angle: .pi, axis: simd_float3(0, 1, 0))
        }

        let axis = simd_normalize(simd_cross(from, direction))
        let angle = acos(min(max(dot, -1), 1))
        return simd_quatf(angle: angle, axis: axis)
    }

    /// Resolves the footprint angle using per-program coverage assumptions.
    private func coverageHalfAngleRadians(for trackedSatellite: TrackedSatellite) -> Double? {
        let descriptor = SatelliteProgramCatalog.descriptor(for: trackedSatellite.satellite)
        switch descriptor.coverageEstimateModel {
        case .minimumElevationDegrees(let minimumElevationDegrees):
            return SatelliteCoverageFootprint.geocentricHalfAngleRadians(
                altitudeKm: trackedSatellite.position.altitudeKm,
                minimumElevationDegrees: minimumElevationDegrees
            )
        case .minimumElevationWithScanLimit(let minimumElevationDegrees, let maxOffNadirDegrees):
            return SatelliteCoverageFootprint.geocentricHalfAngleRadians(
                altitudeKm: trackedSatellite.position.altitudeKm,
                minimumElevationDegrees: minimumElevationDegrees,
                maximumOffNadirDegrees: maxOffNadirDegrees
            )
        case .fixedGroundRadiusKm(let groundRadiusKm):
            return SatelliteCoverageFootprint.geocentricHalfAngleRadians(
                groundRadiusKm: groundRadiusKm
            )
        }
    }
}
