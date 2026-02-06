//
//  GlobeSceneCoordinator+SatelliteLifecycle.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import QuartzCore
@preconcurrency import SceneKit
import simd

/// Satellite-node lifecycle logic for the globe scene.
///
/// This extension manages per-tick satellite updates, node reuse, and
/// model-template/LOD orchestration for SceneKit rendering.
extension GlobeSceneCoordinator {
    /// Updates positions in place and removes nodes for missing satellites.
    func updateSatellites(
        _ tracked: [TrackedSatellite],
        in scene: SCNScene,
        selectedId: Int?
    ) {
        if cameraNode == nil {
            cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
        }
        var shouldUseModel = renderConfig.useModel && !GlobeSceneView.isRunningInPreview
        if shouldUseModel {
            loadSatelliteTemplates()
            shouldUseModel = satelliteHighTemplateNode != nil
        }
        if shouldUseModel != currentUseModel {
            resetSatelliteNodes()
            currentUseModel = shouldUseModel
        }

        if lastYawFollowsOrbit != renderConfig.yawFollowsOrbit {
            // Clear cached axes so we don't keep velocity-based roll when toggling modes.
            lastRightAxis.removeAll()
            lastOrientation.removeAll()
            lastYawFollowsOrbit = renderConfig.yawFollowsOrbit
        }

        updateLodIfNeeded()

        let ids = Set(tracked.map { $0.satellite.id })
        for (id, node) in satelliteNodes where !ids.contains(id) {
            node.removeFromParentNode()
            satelliteNodes[id] = nil
            lastPositions[id] = nil
            lastOrientation[id] = nil
            lastRightAxis[id] = nil
            nodeDetailTiers[id] = nil
            nodeUsesModel[id] = nil
        }

        let tickTimestamp = tracked.first?.position.timestamp
        let previousTickTimestamp = lastTickTimestamp
        let animationDuration: TimeInterval
        if let tickTimestamp, let previousTickTimestamp {
            let delta = tickTimestamp.timeIntervalSince(previousTickTimestamp)
            animationDuration = max(0, min(delta, 1.5))
        } else {
            animationDuration = 0
        }
        lastTickTimestamp = tickTimestamp
        lastAnimationDuration = animationDuration
        let hasNewTick = tickTimestamp != nil && tickTimestamp != previousTickTimestamp

        var updates: [(id: Int, node: SCNNode, position: SCNVector3, trackedSatellite: TrackedSatellite)] = []
        updates.reserveCapacity(tracked.count)

        for trackedSatellite in tracked {
            let id = trackedSatellite.satellite.id
            let desiredTier = resolveDetailTier(
                for: id,
                selectedId: selectedId,
                allowModel: shouldUseModel
            )
            let node = satelliteNodes[id] ?? makeSatelliteNode(
                for: trackedSatellite,
                in: scene,
                allowModel: shouldUseModel,
                detailTier: desiredTier
            )
            if nodeDetailTiers[id] != desiredTier {
                // Swap the model tier without recreating the node to avoid selection jitter.
                applyDetailTier(desiredTier, to: node, id: id)
                nodeDetailTiers[id] = desiredTier
            }
            let position = GlobeCoordinateConverter.scenePosition(
                from: trackedSatellite.position,
                earthRadiusScene: GlobeSceneView.earthRadiusScene
            )
            updates.append((id: id, node: node, position: position, trackedSatellite: trackedSatellite))
        }

        // Animate positions so satellites glide between 1Hz tracking ticks.
        SCNTransaction.begin()
        SCNTransaction.disableActions = animationDuration == 0
        SCNTransaction.animationDuration = animationDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        for update in updates {
            update.node.position = update.position
        }
        SCNTransaction.commit()

        // Update orientation and scale without implicit SceneKit animations.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        let shouldApplyScale = lastScale != renderConfig.scale
        for update in updates {
            if hasNewTick || lastOrientation[update.id] == nil {
                // Only recompute attitude when we receive a new ephemeris tick.
                // This prevents selection taps from briefly snapping the model
                // to a fallback axis when the position hasn't advanced yet.
                applyOrientation(
                    for: update.id,
                    node: update.node,
                    currentPosition: update.position,
                    trackedSatellite: update.trackedSatellite
                )
            }
            if shouldUseModel, nodeUsesModel[update.id] == true {
                let scale = renderConfig.scale
                if shouldApplyScale || update.node.scale.x != scale {
                    applyModelScale(scale, to: update.node)
                }
            }
        }

        // Update the selection indicator once after all satellites are processed.
        if let selectedId,
           let selectedUpdate = updates.first(where: { $0.id == selectedId }) {
            updateSelectionIndicator(
                attachedTo: selectedUpdate.node,
                satelliteId: selectedUpdate.id,
                in: scene
            )
        } else {
            clearSelectionIndicator()
        }
        SCNTransaction.commit()

        if shouldUseModel {
            lastScale = renderConfig.scale
        }

        publishStats(trackedCount: tracked.count, shouldUseModel: shouldUseModel)
    }

    /// Creates a satellite node, using USDZ when available and storing it for reuse.
    private func makeSatelliteNode(
        for tracked: TrackedSatellite,
        in scene: SCNScene,
        allowModel: Bool,
        detailTier: DetailTier
    ) -> SCNNode {
        let node: SCNNode
        if allowModel, let modelNode = loadTemplateNode(for: detailTier)?.clone() {
            // Use the model node directly so its pivot stays aligned with the satellite origin.
            node = modelNode
            nodeDetailTiers[tracked.satellite.id] = detailTier
            nodeUsesModel[tracked.satellite.id] = true
        } else {
            let geometry = SCNSphere(radius: 0.015)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemYellow
            geometry.materials = [material]
            let sphereNode = SCNNode(geometry: geometry)
            node = sphereNode
            nodeDetailTiers[tracked.satellite.id] = .low
            nodeUsesModel[tracked.satellite.id] = false
        }

        let name = String(tracked.satellite.id)
        applyName(name, to: node)
        applyCategory(satelliteCategoryMask, to: node)

        scene.rootNode.addChildNode(node)
        satelliteNodes[tracked.satellite.id] = node
        return node
    }

    /// Loads and caches high/low USDZ templates for cloning.
    private func loadSatelliteTemplates() {
        guard satelliteHighTemplateNode == nil || satelliteLowTemplateNode == nil else { return }
        guard let url = Bundle.main.url(forResource: "BlueBird", withExtension: "usdz"),
              let referenceNode = SCNReferenceNode(url: url) else {
            return
        }
        referenceNode.load()
        tuneSatelliteMaterials(referenceNode)
        if GlobeSceneView.shouldUseSafeMaterials {
            // Simulators use flat materials to avoid USDZ texture format issues.
            GlobeSceneView.applyPreviewSafeMaterials(to: referenceNode, color: .systemYellow)
        }

        // Prefer a flattened clone for performance, but fall back to the full
        // reference node if the flattening step produces no geometry.
        let flattened = referenceNode.flattenedClone()
        let flattenedGeometry = flattened.geometry ?? firstGeometry(in: flattened)
        let flattenedExtent = maxExtent(for: flattened)
        let highContent: SCNNode
        let sourceGeometry: SCNGeometry?
        if let flattenedGeometry, flattenedExtent > 0.001 {
            highContent = flattened
            sourceGeometry = flattenedGeometry
        } else {
            let fallback = referenceNode.clone()
            highContent = fallback
            sourceGeometry = fallback.geometry ?? firstGeometry(in: fallback)
        }

        guard sourceGeometry != nil else {
            // If no geometry is available, allow the caller to fall back to spheres.
            satelliteHighTemplateNode = nil
            satelliteLowTemplateNode = nil
            return
        }

        let highNode = SCNNode()
        highNode.addChildNode(highContent)

        // Center the pivot so rotations happen around the model's center of mass.
        let (minBounds, maxBounds) = highContent.boundingBox
        let center = SCNVector3(
            (minBounds.x + maxBounds.x) * 0.5,
            (minBounds.y + maxBounds.y) * 0.5,
            (minBounds.z + maxBounds.z) * 0.5
        )
        // SceneKit pivots are applied before transforms, so negate to move the center to origin.
        highNode.pivot = SCNMatrix4MakeTranslation(-center.x, -center.y, -center.z)

        let lowNode = makeLowDetailTemplate(from: highNode)

        satelliteHighTemplateNode = highNode
        satelliteLowTemplateNode = lowNode
        lastLodDistances = []
        updateLodIfNeeded()
    }

    /// Returns the cached template for the requested detail tier.
    private func loadTemplateNode(for tier: DetailTier) -> SCNNode? {
        loadSatelliteTemplates()
        switch tier {
        case .high:
            return satelliteHighTemplateNode
        case .low:
            return satelliteLowTemplateNode
        }
    }

    /// Builds a low-detail template by simplifying materials while keeping transforms intact.
    private func makeLowDetailTemplate(from highNode: SCNNode) -> SCNNode {
        let lowNode = highNode.clone()
        // Clone geometry so simplifying materials does not mutate the high-detail template.
        lowNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry?.copy() as? SCNGeometry else { return }
            node.geometry = geometry
            Self.applySimplifiedMaterials(to: geometry, color: .systemYellow)
        }
        if let geometry = lowNode.geometry?.copy() as? SCNGeometry {
            lowNode.geometry = geometry
            Self.applySimplifiedMaterials(to: geometry, color: .systemYellow)
        }
        return lowNode
    }

    /// Applies a simplified material set while keeping the original diffuse texture.
    ///
    /// This preserves the visual identity of the satellite without the cost of
    /// normal/roughness/metalness maps that are expensive at large counts.
    private static func applySimplifiedMaterials(to geometry: SCNGeometry, color: UIColor) {
        let sourceMaterial = geometry.materials.first
        let material = SCNMaterial()
        material.diffuse.contents = sourceMaterial?.diffuse.contents ?? color
        material.lightingModel = .blinn
        material.emission.contents = nil
        material.normal.contents = nil
        material.roughness.contents = nil
        material.metalness.contents = nil
        material.ambientOcclusion.contents = nil
        material.transparencyMode = .aOne
        geometry.materials = [material]
    }

    /// Finds the first geometry in a node hierarchy for LOD assignment.
    private func firstGeometry(in node: SCNNode) -> SCNGeometry? {
        if let geometry = node.geometry {
            return geometry
        }
        for child in node.childNodes {
            if let geometry = firstGeometry(in: child) {
                return geometry
            }
        }
        return nil
    }

    /// Computes the largest extent of a node's bounding box for size sanity checks.
    private func maxExtent(for node: SCNNode) -> Float {
        let (minBounds, maxBounds) = node.boundingBox
        let extent = SCNVector3(
            maxBounds.x - minBounds.x,
            maxBounds.y - minBounds.y,
            maxBounds.z - minBounds.z
        )
        return max(extent.x, max(extent.y, extent.z))
    }

    /// Updates LOD thresholds if the render config changes.
    private func updateLodIfNeeded() {
        guard lastLodDistances != renderConfig.lodDistances else { return }
        lastLodDistances = renderConfig.lodDistances
        guard let highTemplate = satelliteHighTemplateNode else { return }
        guard let firstDistance = renderConfig.lodDistances.first else {
            applyLod(nil, to: highTemplate)
            return
        }
        let distance = max(firstDistance, 0.01)
        // LOD keeps the model visible while swapping to simplified materials at distance.
        applyLod(distance, to: highTemplate)
    }

    /// Applies a material-only LOD to all geometries in the template.
    private func applyLod(_ distance: Float?, to node: SCNNode) {
        let applyToGeometry: (SCNGeometry) -> Void = { geometry in
            if let distance {
                let lowGeometry = geometry.copy() as? SCNGeometry ?? geometry
                Self.applySimplifiedMaterials(to: lowGeometry, color: .systemYellow)
                geometry.levelsOfDetail = [
                    SCNLevelOfDetail(geometry: lowGeometry, worldSpaceDistance: CGFloat(distance))
                ]
            } else {
                geometry.levelsOfDetail = nil
            }
        }

        if let geometry = node.geometry {
            applyToGeometry(geometry)
        }
        node.enumerateChildNodes { child, _ in
            if let geometry = child.geometry {
                applyToGeometry(geometry)
            }
        }
    }

    /// Chooses which model tier a satellite should use.
    private func resolveDetailTier(
        for id: Int,
        selectedId: Int?,
        allowModel: Bool
    ) -> DetailTier {
        guard allowModel else { return .low }
        switch renderConfig.detailMode {
        case .lowOnly:
            return .low
        case .lowWithHighForSelection:
            guard renderConfig.maxDetailModels > 0 else { return .low }
            return id == selectedId ? .high : .low
        }
    }

    /// Swaps the model child node to match the desired detail tier.
    private func applyDetailTier(_ tier: DetailTier, to node: SCNNode, id: Int) {
        guard let template = loadTemplateNode(for: tier)?.clone() else { return }
        // Swap the model contents in-place so the satellite keeps its transform.
        node.childNodes.forEach { $0.removeFromParentNode() }
        node.geometry = template.geometry
        node.pivot = template.pivot
        for child in template.childNodes {
            node.addChildNode(child)
        }
        applyName(node.name ?? "", to: node)
        nodeUsesModel[id] = true
    }

}
