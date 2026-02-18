//
//  GlobeSceneCoordinator+CameraPipeline.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
//

import Foundation
import QuartzCore
import SceneKit
import simd

/// Camera pipeline orchestration for the globe scene coordinator.
///
/// Why this exists:
/// - Camera state now lives in `GlobeCameraController`, and this extension wires
///   scene lifecycle events into that single-owner controller.
/// - Focus intent from both tap selection and cross-tab requests must share one path.
///
/// What this does NOT do:
/// - It does not define gesture recognizers. Gesture event mapping lives in
///   `GlobeSceneCoordinator+CameraGestures`.
extension GlobeSceneCoordinator {
    /// Lower follow-distance bound to keep the camera outside Earth's surface.
    private var minimumFollowDistance: Float { 1.35 }

    /// Upper follow-distance bound to stay inside the configured camera far plane.
    private var maximumFollowDistance: Float { 5.5 }

    /// Starts a display link that drives transition and follow interpolation.
    func startCameraFollowDisplayLinkIfNeeded() {
        guard cameraFollowDisplayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleCameraDisplayLinkTick(_:)))
        // Keep dormant until transition/follow mode needs per-frame updates.
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        cameraFollowDisplayLink = link
        lastDisplayLinkTimestamp = nil
    }

    /// Stops the display link used for camera pipeline updates.
    func stopCameraFollowDisplayLink() {
        cameraFollowDisplayLink?.invalidate()
        cameraFollowDisplayLink = nil
        lastDisplayLinkTimestamp = nil
        isPanGestureActive = false
        isPinchGestureActive = false
        isCameraInteractionActive = false
        lastPanTranslation = .zero
    }

    /// Updates camera focus/follow state from SwiftUI intent and per-frame pose updates.
    func updateCameraFocus(
        request: SatelliteFocusRequest?,
        selectedId: Int?,
        tracked _: [TrackedSatellite],
        in scene: SCNScene
    ) {
        _ = ensureCameraController(in: scene)

        if let request, selectedId == request.satelliteId {
            // Cross-tab focus requests flow through the same request queue as local taps.
            requestFocus(satelliteId: request.satelliteId, token: request.token, in: scene)
        }

        if selectedId == nil, request == nil, pendingFocusRequest == nil {
            // Preserve reset-home transitions, but stop satellite follow when selection clears.
            cameraController?.clearSelection(preserveResetTransition: true)
            pendingFocusRequest = nil
        }

        processPendingFocusIfPossible()
        cameraController?.tick(frameDelta: nominalFrameDelta)
        updateDisplayLinkPauseState()
    }

    /// Queues and processes one focus request from either local tap or cross-tab navigation.
    func requestFocus(satelliteId: Int, token: UUID, in scene: SCNScene?) {
        if let scene {
            _ = ensureCameraController(in: scene)
        }
        pendingFocusRequest = SatelliteFocusRequest(satelliteId: satelliteId, token: token)
        processPendingFocusIfPossible()
        updateDisplayLinkPauseState()
    }

    /// Stops satellite-follow behavior and clears queued focus work.
    func disableAutoFollow() {
        pendingFocusRequest = nil
        cameraController?.clearSelection()
        updateDisplayLinkPauseState()
    }

    /// Camera mode projection for diagnostics overlays.
    var cameraModeForStats: GlobeCameraMode {
        cameraController?.mode ?? .freeOrbit
    }

    /// Camera distance projection for diagnostics overlays.
    var cameraDistanceForStats: Float {
        cameraController?.distance ?? 0
    }

    /// Follow target projection for diagnostics overlays.
    var cameraFollowSatelliteIdForStats: Int? {
        cameraController?.followSatelliteId
    }

    /// Advances camera interpolation and follow on each display refresh tick.
    @objc private func handleCameraDisplayLinkTick(_ link: CADisplayLink) {
        let delta: Float
        if let lastTimestamp = lastDisplayLinkTimestamp {
            delta = Float(max(0.001, min(0.1, link.timestamp - lastTimestamp)))
        } else {
            delta = nominalFrameDelta
        }
        lastDisplayLinkTimestamp = link.timestamp

        guard let scene = view?.scene else { return }
        _ = ensureCameraController(in: scene)
        if cameraController?.state.activeGesture == .pan {
            // Pan owns camera direction updates, so follow ticks are paused while dragging.
            return
        }
        cameraController?.tick(frameDelta: delta)
        updateDisplayLinkPauseState()
    }

    /// Attempts to start a queued focus request when the scene and camera are ready.
    func processPendingFocusIfPossible() {
        if cameraController?.state.activeGesture != nil || isCameraInteractionActive {
            return
        }
        guard let pendingFocusRequest else { return }
        guard let cameraController else { return }

        let started = cameraController.requestFocus(
            satelliteId: pendingFocusRequest.satelliteId,
            token: pendingFocusRequest.token
        )

        // Duplicate tokens are treated as already-consumed and should not stay queued.
        if started || cameraController.state.lastFocusToken == pendingFocusRequest.token {
            self.pendingFocusRequest = nil
        }
    }

    /// Ensures we have one camera node and one camera controller bound together.
    @discardableResult
    func ensureCameraController(in scene: SCNScene) -> GlobeCameraController? {
        guard let managedCameraNode = managedCameraNode(in: scene) else { return nil }

        if cameraController == nil {
            let controller = GlobeCameraController(
                homeCameraPosition: homeCameraPosition,
                selectionZoomMultiplier: selectionZoomMultiplier,
                minimumFollowDistance: minimumFollowDistance,
                maximumFollowDistance: maximumFollowDistance,
                maxPitchRadians: GlobeSceneView.maxCameraPitchAngleRadians
            )
            controller.satelliteDirectionProvider = { [weak self] satelliteId in
                guard let self, let node = self.satelliteNodes[satelliteId] else { return nil }
                let position = node.presentation.position
                return simd_float3(position.x, position.y, position.z)
            }
            cameraController = controller
        }

        cameraController?.attachCameraNode(managedCameraNode)
        return cameraController
    }

    /// Locates and caches the managed camera node.
    private func managedCameraNode(in scene: SCNScene) -> SCNNode? {
        if cameraNode == nil {
            cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
        }
        return cameraNode
    }

    /// Pauses the display link when there is no active transition/follow work.
    func updateDisplayLinkPauseState() {
        cameraFollowDisplayLink?.isPaused = !(cameraController?.requiresDisplayLinkUpdates ?? false)
    }
}
