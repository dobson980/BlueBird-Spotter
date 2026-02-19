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

        desiredOrbitPathSignatures = desiredSignatures
        orbitPathBuildContext = OrbitPathBuildContext(
            referenceDate: referenceDate,
            sampleCount: effectiveSampleCount,
            altitudeOffsetKm: config.altitudeOffsetKm,
            priority: mode == .all ? .utility : .userInitiated,
            generation: orbitPathBuildGeneration
        )

        removeOrbitPaths(excluding: desiredSignatures)
        enqueueMissingOrbitPathBuilds(
            desired: desiredSignatures,
            representative: representative
        )
        drainOrbitPathBuildQueueIfNeeded()
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
        orbitPathBuildQueue.removeAll()
        queuedOrbitPathSignatures.removeAll()
        desiredOrbitPathSignatures.removeAll()
        orbitPathBuildContext = nil
        // Any completion from pre-clear tasks should be ignored.
        orbitPathBuildGeneration &+= 1
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

        guard !orbitPathBuildQueue.isEmpty else { return }

        var trimmedQueue: [OrbitPathBuildRequest] = []
        trimmedQueue.reserveCapacity(orbitPathBuildQueue.count)
        for request in orbitPathBuildQueue where desired.contains(request.signature) {
            trimmedQueue.append(request)
        }
        orbitPathBuildQueue = trimmedQueue
        queuedOrbitPathSignatures = Set(trimmedQueue.map { $0.signature })
    }

    /// Adds missing orbit signatures to the pending background-build queue.
    private func enqueueMissingOrbitPathBuilds(
        desired: Set<OrbitSignature>,
        representative: [OrbitSignature: Satellite]
    ) {
        for signature in desired {
            guard orbitPathNodes[signature] == nil,
                  orbitPathTasks[signature] == nil,
                  !queuedOrbitPathSignatures.contains(signature),
                  let satellite = representative[signature] else { continue }

            orbitPathBuildQueue.append(
                OrbitPathBuildRequest(
                    signature: signature,
                    satellite: satellite
                )
            )
            queuedOrbitPathSignatures.insert(signature)
        }
    }

    /// Starts queued orbit builds up to the configured concurrency cap.
    private func drainOrbitPathBuildQueueIfNeeded() {
        guard let context = orbitPathBuildContext else { return }

        while orbitPathTasks.count < Self.maxConcurrentOrbitPathBuilds,
              let request = popNextOrbitPathBuildRequest() {
            guard orbitPathNodes[request.signature] == nil,
                  orbitPathTasks[request.signature] == nil,
                  desiredOrbitPathSignatures.contains(request.signature) else {
                continue
            }

            launchOrbitPathBuild(for: request, context: context)
        }
    }

    /// Pops the next queued orbit build request while keeping de-dupe bookkeeping in sync.
    private func popNextOrbitPathBuildRequest() -> OrbitPathBuildRequest? {
        guard !orbitPathBuildQueue.isEmpty else { return nil }
        let request = orbitPathBuildQueue.removeFirst()
        queuedOrbitPathSignatures.remove(request.signature)
        return request
    }

    /// Launches one detached build task and handles completion on the main actor.
    private func launchOrbitPathBuild(for request: OrbitPathBuildRequest, context: OrbitPathBuildContext) {
        let signature = request.signature
        let satellite = request.satellite

        // Detached work avoids inheriting main-actor context for heavy orbit math.
        let task = Task.detached(priority: context.priority) {
            GlobeOrbitPathBuilder.buildOrbitPathVertices(
                for: satellite,
                referenceDate: context.referenceDate,
                sampleCount: context.sampleCount,
                altitudeOffsetKm: context.altitudeOffsetKm
            )
        }

        orbitPathTasks[signature] = task

        Task { @MainActor [weak self] in
            guard let self else { return }
            let vertices = await task.value
            self.orbitPathTasks[signature] = nil

            defer {
                // Continue draining immediately so we are not gated by the next SwiftUI tick.
                self.drainOrbitPathBuildQueueIfNeeded()
            }

            guard context.generation == self.orbitPathBuildGeneration,
                  self.orbitPathNodes[signature] == nil,
                  self.desiredOrbitPathSignatures.contains(signature),
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
            // Start transparent, then fade in to remove hard pop-in of completed paths.
            node.opacity = 0
            self.view?.scene?.rootNode.addChildNode(node)
            self.orbitPathNodes[signature] = node

            SCNTransaction.begin()
            SCNTransaction.animationDuration = Self.orbitPathFadeInDuration
            node.opacity = 1
            SCNTransaction.commit()
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
