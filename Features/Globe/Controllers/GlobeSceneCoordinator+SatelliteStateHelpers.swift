//
//  GlobeSceneCoordinator+SatelliteStateHelpers.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import SceneKit
import simd

/// Orientation, selection, and node-state helpers for satellite rendering.
///
/// These methods are separated from lifecycle orchestration to keep files small
/// and make satellite transform logic easier to review in isolation.
extension GlobeSceneCoordinator {
    /// Applies the render scale to model children without affecting the parent position.
    func applyModelScale(_ scale: Float, to node: SCNNode) {
        let scaleVector = SCNVector3(scale, scale, scale)
        if !matchesScale(node.scale, scaleVector) {
            node.scale = scaleVector
        }
    }


    /// Emits render diagnostics for debug overlays.
    func publishStats(trackedCount: Int, shouldUseModel: Bool) {
        guard let onStats else { return }
        let stats = GlobeRenderStats(
            trackedCount: trackedCount,
            nodeCount: satelliteNodes.count,
            usesModelTemplates: shouldUseModel,
            templateLoaded: satelliteHighTemplateNode != nil,
            isPreview: GlobeSceneView.isRunningInPreview,
            isSimulator: GlobeSceneView.isRunningInSimulator
        )
        onStats(stats)
    }

    /// Compares SceneKit vectors without relying on Equatable conformance.
    private func matchesScale(_ lhs: SCNVector3, _ rhs: SCNVector3) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }

    /// Computes orientation so the model points toward Earth and optionally along velocity.
    func applyOrientation(
        for id: Int,
        node: SCNNode,
        currentPosition: SCNVector3,
        trackedSatellite: TrackedSatellite
    ) {
        defer { lastPositions[id] = currentPosition }

        let config = renderConfig
        let baseOffset = baseOrientationQuaternion(for: config)
        guard config.nadirPointing else {
            node.simdOrientation = baseOffset
            lastOrientation[id] = baseOffset
            return
        }

        let position = currentPosition.simd
        let distance = simd_length(position)
        guard distance > 0 else {
            node.simdOrientation = baseOffset
            lastOrientation[id] = baseOffset
            return
        }

        // Model forward is assumed to be -Z, so +Z points away from Earth.
        let outward = position / distance
        let radial = -outward

        let right = preferredRightAxis(
            for: id,
            radial: radial,
            outward: outward,
            currentPosition: currentPosition,
            trackedSatellite: trackedSatellite
        )
        let up = simd_normalize(simd_cross(outward, right))

        let basis = simd_float3x3(columns: (right, up, outward))
        let orientation = simd_quatf(basis)

        // Apply a heading offset around the radial axis to align the long face with the orbit line.
        let headingOffset = config.orbitHeadingOffset
        let headingRotation = headingOffset == 0
            ? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            : simd_quatf(angle: headingOffset, axis: outward)
        // Apply base offsets after attitude so artists can correct model alignment.
        let targetOrientation = headingRotation * orientation * baseOffset
        if let last = lastOrientation[id] {
            // Slerp smooths orientation changes to prevent visible snapping on tick boundaries.
            node.simdOrientation = simd_slerp(last, targetOrientation, 0.35)
        } else {
            node.simdOrientation = targetOrientation
        }
        lastOrientation[id] = node.simdOrientation
    }

    /// Picks a stable right axis, favoring velocity tangent when enabled.
    ///
    /// Uses the provided SGP4 velocity on the first tick so satellites load with
    /// the correct orbit-following orientation immediately. Subsequent ticks use
    /// position delta for smoother tracking.
    private func preferredRightAxis(
        for id: Int,
        radial: simd_float3,
        outward: simd_float3,
        currentPosition: SCNVector3,
        trackedSatellite: TrackedSatellite
    ) -> simd_float3 {
        if renderConfig.yawFollowsOrbit {
            // Try position-based velocity first (more stable for animation).
            if let previous = lastPositions[id] {
                let velocity = (currentPosition - previous).simd
                let velocityLength = simd_length(velocity)
                if velocityLength > 0 {
                    let velocityDir = velocity / velocityLength
                    let projected = velocityDir - radial * simd_dot(velocityDir, radial)
                    if simd_length(projected) > 0.0001 {
                        var stabilized = simd_normalize(projected)
                        if let cached = lastRightAxis[id], simd_dot(stabilized, cached) < 0 {
                            stabilized = -stabilized
                        }
                        lastRightAxis[id] = stabilized
                        return stabilized
                    }
                }
            }

            // First tick: use SGP4-provided velocity for correct initial orientation.
            if let velocityKmPerSec = trackedSatellite.position.velocityKmPerSec {
                let velocityDir = GlobeCoordinateConverter.sceneVelocityDirection(
                    from: velocityKmPerSec,
                    at: trackedSatellite.position.timestamp
                )
                let projected = velocityDir - radial * simd_dot(velocityDir, radial)
                if simd_length(projected) > 0.0001 {
                    var stabilized = simd_normalize(projected)
                    if let cached = lastRightAxis[id], simd_dot(stabilized, cached) < 0 {
                        stabilized = -stabilized
                    }
                    lastRightAxis[id] = stabilized
                    return stabilized
                }
            }
        }

        // Fallback: use cached axis or world-up.
        if let cached = lastRightAxis[id] {
            return cached
        }

        let worldUp = simd_float3(0, 1, 0)
        var right = simd_cross(worldUp, outward)
        if simd_length(right) < 0.0001 {
            right = simd_cross(simd_float3(1, 0, 0), outward)
        }
        let stabilized = simd_normalize(right)
        lastRightAxis[id] = stabilized
        return stabilized
    }


    /// Builds the base yaw/pitch/roll offsets as a quaternion.
    private func baseOrientationQuaternion(for config: SatelliteRenderConfig) -> simd_quatf {
        let yaw = simd_quatf(angle: config.baseYaw, axis: simd_float3(0, 1, 0))
        let pitch = simd_quatf(angle: config.basePitch, axis: simd_float3(1, 0, 0))
        let roll = simd_quatf(angle: config.baseRoll, axis: simd_float3(0, 0, 1))
        return yaw * pitch * roll
    }

    /// Adds or updates the selection halo attached to the selected satellite node.
    ///
    /// The indicator is parented to the satellite so it inherits the satellite's
    /// orientation, keeping the ring aligned with the model.
    func updateSelectionIndicator(
        attachedTo satelliteNode: SCNNode,
        satelliteId: Int,
        in scene: SCNScene
    ) {
        let indicator = selectionIndicatorNode ?? makeSelectionIndicatorNode()
        let usesModelTemplate = nodeUsesModel[satelliteId] ?? false

        // Fallback geometry nodes are unscaled, so apply the render scale manually
        // to keep the halo comparable with model-backed satellites.
        if usesModelTemplate {
            indicator.scale = SCNVector3(1, 1, 1)
        } else {
            let fallbackScale = max(renderConfig.scale, 0.0005)
            indicator.scale = SCNVector3(fallbackScale, fallbackScale, fallbackScale)
        }

        // Move the indicator when selection changes, otherwise reuse in place.
        if indicator.parent != satelliteNode {
            indicator.removeFromParentNode()
            satelliteNode.addChildNode(indicator)

            // Position at local origin so it centers on the satellite.
            indicator.position = SCNVector3Zero
        }

        updateSelectionMaterial(for: indicator, color: selectionColor)
        selectionIndicatorNode = indicator
    }

    /// Removes the selection halo when no satellite is selected.
    func clearSelectionIndicator() {
        selectionIndicatorNode?.removeFromParentNode()
        selectionIndicatorNode = nil
    }

    /// Builds the selection indicator node once and reuses it for the current selection.
    ///
    /// The indicator is a flat glowing disk that sits behind the satellite
    /// as a simple visual marker for selection.
    private func makeSelectionIndicatorNode() -> SCNNode {
        // Use a flat plane for simplicity - no 3D depth needed.
        let disk = SCNPlane(width: 26, height: 26)
        disk.cornerRadius = 13  // Make it circular.
        let material = SCNMaterial()
        material.diffuse.contents = selectionColor
        material.emission.contents = selectionColor
        material.emission.intensity = 0.6
        material.lightingModel = .constant
        material.isDoubleSided = true
        // Use alpha blending instead of additive to prevent background bleed-through.
        material.blendMode = .alpha
        disk.materials = [material]

        let haloNode = SCNNode(geometry: disk)
        // No rotation - the plane faces +Z by default, which aligns with the
        // satellite's nadir-pointing orientation (Earth is in the -Z direction
        // of the satellite's local space when nadir-pointing is enabled).
        // Position behind the satellite toward Earth.
        haloNode.position.z = 3.0
        // Slightly transparent for a softer look.
        haloNode.opacity = 0.7
        // Render behind the satellite and orbit paths.
        haloNode.renderingOrder = -10
        // Use the satellite category so the camera renders this node.
        haloNode.categoryBitMask = satelliteCategoryMask
        return haloNode
    }

    /// Updates the halo material when the user picks a new path color.
    private func updateSelectionMaterial(for node: SCNNode, color: UIColor) {
        guard let geometry = node.geometry else { return }
        for material in geometry.materials {
            material.diffuse.contents = color
            material.emission.contents = color
        }
    }

    /// Walks up the node hierarchy to find the satellite id string.
    func resolveSatelliteId(from node: SCNNode) -> Int? {
        var current: SCNNode? = node
        while let candidate = current {
            if let name = candidate.name, let id = Int(name) {
                return id
            }
            current = candidate.parent
        }
        return nil
    }

    /// Applies a stable name to every node in the hierarchy for hit testing.
    func applyName(_ name: String, to node: SCNNode) {
        node.name = name
        for child in node.childNodes {
            applyName(name, to: child)
        }
    }

    /// Applies a SceneKit category bitmask to the node hierarchy.
    func applyCategory(_ mask: Int, to node: SCNNode) {
        node.categoryBitMask = mask
        for child in node.childNodes {
            applyCategory(mask, to: child)
        }
    }

    /// Clears cached nodes when the rendering mode changes.
    func resetSatelliteNodes() {
        for node in satelliteNodes.values {
            node.removeFromParentNode()
        }
        satelliteNodes.removeAll()
        lastPositions.removeAll()
        lastOrientation.removeAll()
        lastRightAxis.removeAll()
        lastTickTimestamp = nil
        lastAnimationDuration = 0
        nodeDetailTiers.removeAll()
        nodeUsesModel.removeAll()
        lastScale = nil
        for node in coverageNodes.values {
            node.removeFromParentNode()
        }
        coverageNodes.removeAll()
        coverageGeometryKeys.removeAll()
    }

    /// Normalizes satellite materials for stable, opaque rendering near screen edges.
    func tuneSatelliteMaterials(_ root: SCNNode) {
        let applyToMaterials: ([SCNMaterial]) -> Void = { materials in
            for material in materials {
                let properties: [SCNMaterialProperty] = [
                    material.diffuse,
                    material.emission,
                    material.normal,
                    material.roughness,
                    material.metalness,
                    material.ambientOcclusion,
                    material.transparent
                ]
                for property in properties {
                    property.magnificationFilter = .linear
                    property.minificationFilter = .linear
                    property.mipFilter = .linear
                    property.maxAnisotropy = 16
                }

                material.blendMode = .replace
                material.transparencyMode = .aOne
                material.writesToDepthBuffer = true
                material.readsFromDepthBuffer = true

            }
        }

        if let materials = root.geometry?.materials {
            applyToMaterials(materials)
        }

        root.enumerateChildNodes { node, _ in
            guard let materials = node.geometry?.materials else { return }
            applyToMaterials(materials)
        }
    }

}
