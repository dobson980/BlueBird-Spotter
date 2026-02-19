//
//  GlobeSceneCoordinator+OrbitPaths.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/6/26.
//

import SceneKit
import simd

/// Orbit-path rendering and asynchronous path-build orchestration.
///
/// This extension owns deduplication, build-task scheduling, and Earth-rotation
/// alignment so orbit visuals stay correct and responsive.
extension GlobeSceneCoordinator {
    /// Renders orbital paths based on the selected mode, deduping shared orbits.
    func updateOrbitPaths(
        for tracked: [TrackedSatellite],
        selectedId: Int?,
        mode: OrbitPathMode,
        config: OrbitPathConfig
    ) {
        if lastOrbitPathConfig != config {
            clearOrbitPaths()
            lastOrbitPathConfig = config
        }

        let referenceDate = tracked.first?.position.timestamp ?? Date()
        applyOrbitRotation(for: referenceDate)

        let signaturesById = buildOrbitSignatures(from: tracked)
        let representative = buildRepresentativeSatellites(from: tracked, signatures: signaturesById)
        let desiredSignatures: Set<OrbitSignature>

        switch mode {
        case .off:
            desiredSignatures = []
        case .selectedOnly:
            if let selectedId,
               let signature = signaturesById[selectedId] {
                desiredSignatures = [signature]
            } else {
                desiredSignatures = []
            }
        case .all:
            desiredSignatures = Set(signaturesById.values)
        }

        let effectiveSampleCount = GlobeOrbitPathBuilder.effectiveSampleCount(
            for: mode,
            desiredCount: desiredSignatures.count,
            baseSampleCount: config.sampleCount
        )
        if lastOrbitPathSampleCount != effectiveSampleCount {
            clearOrbitPaths()
            lastOrbitPathSampleCount = effectiveSampleCount
        }

        removeOrbitPaths(excluding: desiredSignatures)
        buildMissingOrbitPaths(
            desired: desiredSignatures,
            representative: representative,
            config: config,
            referenceDate: referenceDate,
            sampleCount: effectiveSampleCount,
            priority: mode == .all ? .utility : .userInitiated
        )
    }

    /// Removes all cached orbit paths and cancels in-flight builds.
    private func clearOrbitPaths() {
        for node in orbitPathNodes.values {
            node.removeFromParentNode()
        }
        orbitPathNodes.removeAll()
        for task in orbitPathTasks.values {
            task.cancel()
        }
        orbitPathTasks.removeAll()
    }

    /// Builds a map of satellite ids to their deduped orbit signatures.
    private func buildOrbitSignatures(from tracked: [TrackedSatellite]) -> [Int: OrbitSignature] {
        var signatures: [Int: OrbitSignature] = [:]
        for trackedSatellite in tracked {
            if let signature = OrbitSignature(tleLine2: trackedSatellite.satellite.tleLine2) {
                signatures[trackedSatellite.satellite.id] = signature
            }
        }
        return signatures
    }

    /// Picks a single representative satellite for each shared orbit signature.
    private func buildRepresentativeSatellites(
        from tracked: [TrackedSatellite],
        signatures: [Int: OrbitSignature]
    ) -> [OrbitSignature: Satellite] {
        var representatives: [OrbitSignature: Satellite] = [:]
        for trackedSatellite in tracked {
            guard let signature = signatures[trackedSatellite.satellite.id] else { continue }
            if representatives[signature] == nil {
                representatives[signature] = trackedSatellite.satellite
            }
        }
        return representatives
    }

    /// Removes orbit paths that are no longer required by the active mode.
    private func removeOrbitPaths(excluding desired: Set<OrbitSignature>) {
        for (signature, node) in orbitPathNodes where !desired.contains(signature) {
            node.removeFromParentNode()
            orbitPathNodes[signature] = nil
        }
        for (signature, task) in orbitPathTasks where !desired.contains(signature) {
            task.cancel()
            orbitPathTasks[signature] = nil
        }
    }

    /// Builds missing orbital paths asynchronously for the requested signatures.
    private func buildMissingOrbitPaths(
        desired: Set<OrbitSignature>,
        representative: [OrbitSignature: Satellite],
        config: OrbitPathConfig,
        referenceDate: Date,
        sampleCount: Int,
        priority: TaskPriority
    ) {
        let altitudeOffsetKm = config.altitudeOffsetKm

        for signature in desired {
            if orbitPathTasks.count >= Self.maxConcurrentOrbitPathBuilds {
                break
            }
            guard orbitPathNodes[signature] == nil,
                  orbitPathTasks[signature] == nil,
                  let satellite = representative[signature] else { continue }

            let task = Task.detached(priority: priority) {
                return GlobeOrbitPathBuilder.buildOrbitPathVertices(
                    for: satellite,
                    referenceDate: referenceDate,
                    sampleCount: sampleCount,
                    altitudeOffsetKm: altitudeOffsetKm
                )
            }

            orbitPathTasks[signature] = task

            Task { @MainActor [weak self] in
                guard let self else { return }
                let vertices = await task.value
                self.orbitPathTasks[signature] = nil

                guard !Task.isCancelled,
                      self.orbitPathNodes[signature] == nil,
                      desired.contains(signature),
                      vertices.count > 1 else { return }

                guard let config = self.lastOrbitPathConfig else { return }
                let node = GlobeOrbitPathBuilder.makeOrbitPathNode(
                    vertices: vertices,
                    config: config,
                    categoryMask: self.orbitPathCategoryMask
                )
                if let rotation = self.lastOrbitRotation {
                    node.simdOrientation = rotation
                }
                self.view?.scene?.rootNode.addChildNode(node)
                self.orbitPathNodes[signature] = node
            }
        }
    }

    /// Aligns orbit path nodes with the current Earth rotation angle.
    private func applyOrbitRotation(for date: Date) {
        let gmstRadians = EarthCoordinateConverter.gmstRadians(for: date)
        // Rotate inertial (TEME) paths into the Earth-fixed frame used by the globe.
        let rotation = simd_quatf(angle: Float(-gmstRadians), axis: simd_float3(0, 1, 0))
        lastOrbitRotation = rotation
        for node in orbitPathNodes.values {
            node.simdOrientation = rotation
        }
    }

}
