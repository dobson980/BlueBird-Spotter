//
//  GlobeSceneCoordinator+CameraAndGestures.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import SceneKit
import UIKit
import simd

/// Camera focus, lighting, and gesture behavior for the globe scene.
///
/// Keeping these methods together makes it easier for contributors to find
/// all user-interaction and camera-transition logic in one place.
extension GlobeSceneCoordinator {
    /// Camera distance used when focusing a selected satellite.
    ///
    /// We intentionally zoom in relative to the home camera distance so each
    /// selection is easier to inspect while still keeping Earth context visible.
    private var selectionFocusDistance: Float {
        let homeDistance = simd_length(
            simd_float3(homeCameraPosition.x, homeCameraPosition.y, homeCameraPosition.z)
        )
        return max(0.6, homeDistance * selectionZoomMultiplier)
    }

    /// Starts a display link that keeps camera follow updates smooth between data ticks.
    func startCameraFollowDisplayLinkIfNeeded() {
        guard cameraFollowDisplayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleCameraFollowDisplayLinkTick(_:)))
        // Keep the link dormant until a satellite is selected for follow.
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        cameraFollowDisplayLink = link
        lastDisplayLinkTimestamp = nil
    }

    /// Stops the display link used for camera follow updates.
    func stopCameraFollowDisplayLink() {
        cameraFollowDisplayLink?.invalidate()
        cameraFollowDisplayLink = nil
        lastDisplayLinkTimestamp = nil
        isCameraInteractionActive = false
        activeCameraInteractionCount = 0
        needsFollowCameraReacquire = false
    }

    /// Advances camera follow at display refresh cadence for smooth motion.
    @objc private func handleCameraFollowDisplayLinkTick(_ link: CADisplayLink) {
        let delta: Float
        if let lastTimestamp = lastDisplayLinkTimestamp {
            delta = Float(max(0.001, min(0.1, link.timestamp - lastTimestamp)))
        } else {
            delta = nominalFrameDelta
        }
        lastDisplayLinkTimestamp = link.timestamp

        if isCameraInteractionActive {
            return
        }

        guard let scene = view?.scene else { return }
        updateAutoFollowCamera(in: scene, frameDelta: delta)
    }

    /// Temporarily stops follow without clearing an in-flight pending focus.
    ///
    /// We use this while switching targets so the old follow target does not
    /// fight with the incoming focus animation.
    private func suspendAutoFollow() {
        autoFollowSatelliteId = nil
        isAutoFollowEnabled = false
        lastAutoFollowDirection = nil
        cameraFollowDisplayLink?.isPaused = true
        needsFollowCameraReacquire = false
    }

    /// Lower follow-distance bound to keep the camera outside Earth's surface.
    private var minimumFollowDistance: Float { 1.02 }

    /// Upper follow-distance bound to stay inside the configured camera far plane.
    private var maximumFollowDistance: Float { 11.0 }

    /// Returns the dedicated globe camera node tracked by this coordinator.
    private func managedCameraNode(in scene: SCNScene) -> SCNNode? {
        if cameraNode == nil {
            cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
        }
        return cameraNode
    }

    /// Returns whichever camera node is currently visible to the user.
    ///
    /// SceneKit can temporarily render from a controller-owned POV while gestures
    /// are in progress. Reading from the visible POV avoids starting new focus
    /// animations from stale coordinates.
    private func visibleCameraNode(in scene: SCNScene) -> SCNNode? {
        if let view, let controllerPointOfView = view.defaultCameraController.pointOfView {
            return controllerPointOfView
        }
        if let view, let pointOfView = view.pointOfView {
            return pointOfView
        }
        if let cameraNode {
            return cameraNode
        }
        return scene.rootNode.childNode(withName: "globeCamera", recursively: false)
    }

    /// Captures the currently visible camera pose as a normalized direction + distance pair.
    ///
    /// Focus transitions use this snapshot so each selection starts from the camera
    /// pose the user is actually seeing on-screen.
    private func captureVisibleCameraPose(in scene: SCNScene) -> (direction: simd_float3, distance: Float)? {
        guard let sourceNode = visibleCameraNode(in: scene) else { return nil }
        let sourcePosition = sourceNode.presentation.position
        let sourceVector = simd_float3(sourcePosition.x, sourcePosition.y, sourcePosition.z)
        let sourceDistance = simd_length(sourceVector)
        guard sourceDistance.isFinite, sourceDistance > 0.001 else { return nil }
        let sourceDirection = sourceVector / sourceDistance
        guard sourceDirection.x.isFinite,
              sourceDirection.y.isFinite,
              sourceDirection.z.isFinite else {
            return nil
        }
        return (sourceDirection, sourceDistance)
    }

    /// Binds both SceneKit camera owners to our managed globe camera node.
    private func bindManagedCamera(to view: SCNView, in scene: SCNScene) -> SCNNode? {
        guard let cameraNode = managedCameraNode(in: scene) else { return nil }
        view.pointOfView = cameraNode
        view.defaultCameraController.pointOfView = cameraNode
        return cameraNode
    }

    /// Copies the user-visible camera transform into the managed globe camera.
    ///
    /// This keeps focus transitions anchored to the camera pose that is currently
    /// on screen, eliminating jumps to an older model-space transform.
    @discardableResult
    private func syncManagedCameraToVisibleState(in scene: SCNScene) -> SCNNode? {
        guard let cameraNode = managedCameraNode(in: scene) else { return nil }
        let sourceNode = visibleCameraNode(in: scene) ?? cameraNode
        let sourceTransform = sourceNode.presentation.simdWorldTransform
        let sourceTranslation = sourceTransform.columns.3
        guard sourceTranslation.x.isFinite,
              sourceTranslation.y.isFinite,
              sourceTranslation.z.isFinite else {
            return cameraNode
        }
        cameraNode.simdWorldTransform = sourceTransform
        return cameraNode
    }

    /// Takes explicit camera ownership before programmatic focus/reset animation.
    ///
    /// Stopping inertia here prevents SceneKit's camera controller from "catching up"
    /// to an older gesture state right after we begin our custom orbit animation.
    private func prepareManagedCameraForProgrammaticMotion(in scene: SCNScene) -> SCNNode? {
        guard let view else {
            return syncManagedCameraToVisibleState(in: scene)
        }
        view.defaultCameraController.stopInertia()
        _ = syncManagedCameraToVisibleState(in: scene)
        return bindManagedCamera(to: view, in: scene)
    }

    /// Applies conservative safety limits to follow distance values.
    private func clampedFollowDistance(_ distance: Float) -> Float {
        min(max(distance, minimumFollowDistance), maximumFollowDistance)
    }

    /// Updates directional and ambient lighting based on user settings and UTC time.
    func updateLighting(
        in scene: SCNScene,
        isDirectionalLightEnabled: Bool,
        at date: Date
    ) {
        let sunNode = scene.rootNode.childNode(withName: "sunLight", recursively: false)
        let ambientNode = scene.rootNode.childNode(withName: "ambientLight", recursively: false)
        if let sunNode {
            updateSunNodeDirection(sunNode, at: date)
        }

        if isDirectionalLightEnabled {
            sunNode?.light?.intensity = GlobeSceneView.sunLightIntensity
            sunNode?.light?.castsShadow = true
            ambientNode?.light?.intensity = GlobeSceneView.ambientLightIntensity
        } else {
            sunNode?.light?.intensity = 0
            sunNode?.light?.castsShadow = false
            ambientNode?.light?.intensity = GlobeSceneView.ambientLightIntensityWhenDirectionalOff
        }
    }

    /// Orients the directional light using the real-time subsolar point.
    private func updateSunNodeDirection(_ sunNode: SCNNode, at date: Date) {
        let directionToSun = SolarLightingModel.sceneSunDirection(at: date)
        let sunPosition = directionToSun * GlobeSceneView.sunLightNodeDistance
        sunNode.position = SCNVector3(sunPosition.x, sunPosition.y, sunPosition.z)
        // Looking at Earth's center aligns the light ray direction with incoming sunlight.
        sunNode.look(at: SCNVector3Zero)
    }

    /// Centers the camera on a satellite when a focus request is issued.
    func updateCameraFocus(
        request: SatelliteFocusRequest?,
        selectedId: Int?,
        tracked _: [TrackedSatellite],
        in scene: SCNScene
    ) {
        if let request,
           selectedId == request.satelliteId,
           pendingFocusRequest == nil,
           lastFocusToken != request.token {
            lastFocusToken = request.token
            // Pause current follow so this request always starts from current viewport.
            suspendAutoFollow()
            pendingFocusRequest = request
        }

        if let pending = pendingFocusRequest {
            guard !isCameraInteractionActive else { return }
            // Use one shared distance for all entry points (TLE/Tracking/Globe taps)
            // so the camera always lands at the same zoom level for selection.
            if focusCamera(
                on: pending.satelliteId,
                in: scene,
                preferredDistance: selectionFocusDistance
            ) {
                enableAutoFollow(for: pending.satelliteId)
                pendingFocusRequest = nil
            }
        }

        updateAutoFollowCamera(in: scene, frameDelta: nominalFrameDelta)
    }

    /// Moves the camera onto a satellite-centered radial direction.
    ///
    /// Returns `true` when the focus action was started successfully.
    @discardableResult
    private func focusCamera(
        on satelliteId: Int,
        in scene: SCNScene,
        preferredDistance: Float?
    ) -> Bool {
        guard let targetNode = satelliteNodes[satelliteId] else { return false }
        // Freeze any camera-controller inertia before we snapshot the start pose.
        // This prevents follow-up selections from beginning on a drifting transform.
        view?.defaultCameraController.stopInertia()
        // Snapshot the visible pose first so the upcoming focus transition starts
        // from the exact on-screen camera state, including user-driven zoom.
        let startPose = captureVisibleCameraPose(in: scene)
        guard let cameraNode = prepareManagedCameraForProgrammaticMotion(in: scene) else { return false }
        cameraNode.removeAction(forKey: cameraFocusActionKey)

        // Presentation position reflects what the user is actually seeing on screen.
        // Using model position here can cause visible jumps while SceneKit animates.
        let satellitePosition = targetNode.presentation.position
        guard satellitePosition.x.isFinite,
              satellitePosition.y.isFinite,
              satellitePosition.z.isFinite else {
            return false
        }

        let direction = simd_float3(
            satellitePosition.x,
            satellitePosition.y,
            satellitePosition.z
        )
        let directionLength = simd_length(direction)
        guard directionLength > 0.001 else { return false }
        let targetDirection = direction / directionLength

        let cameraPosition = cameraNode.presentation.position
        let cameraVector = simd_float3(cameraPosition.x, cameraPosition.y, cameraPosition.z)
        let syncedDistance = simd_length(cameraVector)
        let currentDistance = startPose?.distance ?? syncedDistance
        let fallbackDistance = selectionFocusDistance
        let desiredDistance: Float
        if let preferredDistance {
            desiredDistance = preferredDistance
        } else if currentDistance.isFinite, currentDistance > 0.25 {
            desiredDistance = currentDistance
        } else {
            desiredDistance = fallbackDistance
        }

        animateCameraOrbit(
            to: targetDirection,
            distance: desiredDistance,
            node: cameraNode,
            startDirection: startPose?.direction,
            startDistance: startPose?.distance
        )
        lastAutoFollowDirection = targetDirection
        return true
    }

    /// Keeps the camera locked onto the followed satellite while auto-follow is enabled.
    private func updateAutoFollowCamera(in scene: SCNScene, frameDelta: Float) {
        guard isAutoFollowEnabled, let satelliteId = autoFollowSatelliteId else { return }
        guard !isCameraInteractionActive else { return }
        guard let satelliteNode = satelliteNodes[satelliteId] else { return }
        guard let cameraNode = managedCameraNode(in: scene) else { return }

        // Let any explicit focus animation complete before continuous follow takes over.
        if cameraNode.action(forKey: cameraFocusActionKey) != nil {
            return
        }

        if let visibleNode = visibleCameraNode(in: scene),
           visibleNode !== cameraNode {
            // If SceneKit is still rendering from a controller-owned POV, defer one
            // re-acquire so follow continues from the user's current pinch zoom.
            needsFollowCameraReacquire = true
        }

        if needsFollowCameraReacquire,
           let view {
            // Defer re-acquire until follow resumes so we capture the final post-gesture
            // camera pose exactly once, avoiding per-frame zoom snapback.
            view.defaultCameraController.stopInertia()
            _ = syncManagedCameraToVisibleState(in: scene)
            _ = bindManagedCamera(to: view, in: scene)
            needsFollowCameraReacquire = false
        }

        let satellitePosition = satelliteNode.presentation.position
        let direction = simd_float3(
            satellitePosition.x,
            satellitePosition.y,
            satellitePosition.z
        )
        let length = simd_length(direction)
        guard length > 0.001 else { return }
        let targetDirection = direction / length

        let followPoseNode = visibleCameraNode(in: scene) ?? cameraNode
        let cameraPosition = followPoseNode.presentation.position
        let currentVector = simd_float3(cameraPosition.x, cameraPosition.y, cameraPosition.z)
        let currentDistance = simd_length(currentVector)
        let modelPosition = cameraNode.position
        let modelVector = simd_float3(modelPosition.x, modelPosition.y, modelPosition.z)
        let modelDistance = simd_length(modelVector)
        let resolvedDistance: Float
        if currentDistance.isFinite, currentDistance > 0.25 {
            resolvedDistance = clampedFollowDistance(currentDistance)
        } else if modelDistance.isFinite, modelDistance > 0.25 {
            resolvedDistance = clampedFollowDistance(modelDistance)
        } else {
            resolvedDistance = clampedFollowDistance(selectionFocusDistance)
        }

        let currentDirection: simd_float3
        if currentDistance.isFinite, currentDistance > 0.001 {
            currentDirection = currentVector / currentDistance
        } else {
            currentDirection = targetDirection
        }

        let clampedDot = simd_clamp(simd_dot(currentDirection, targetDirection), -1.0, 1.0)
        let angularDelta = acos(clampedDot)
        if angularDelta < 0.00005 {
            lastAutoFollowDirection = targetDirection
            return
        }

        // Scale follow speed by delta and target movement so fast passes still feel locked in.
        let frameScale = max(0.25, min(3.0, frameDelta / nominalFrameDelta))
        let baseT = max(0.08, min(0.35, angularDelta * 0.85))
        let interpolationT = max(0.08, min(0.55, baseT * frameScale))
        let nextDirection = slerpDirection(from: currentDirection, to: targetDirection, t: interpolationT)
        let nextPosition = nextDirection * resolvedDistance

        cameraNode.position = SCNVector3(nextPosition.x, nextPosition.y, nextPosition.z)
        cameraNode.look(at: SCNVector3Zero)
        lastAutoFollowDirection = targetDirection
    }

    /// Spherical interpolation helper for smooth camera direction blending.
    private func slerpDirection(from a: simd_float3, to b: simd_float3, t: Float) -> simd_float3 {
        let clampedT = simd_clamp(t, 0, 1)
        let dot = simd_clamp(simd_dot(a, b), -1.0, 1.0)
        let angle = acos(dot)

        if angle < 0.001 {
            return b
        }

        let sinAngle = sin(angle)
        if abs(sinAngle) < 0.0001 {
            // Opposite-direction edge case: fall back to normalized linear blend.
            return simd_normalize(a * (1.0 - clampedT) + b * clampedT)
        }
        let weightA = sin((1.0 - clampedT) * angle) / sinAngle
        let weightB = sin(clampedT * angle) / sinAngle
        return a * weightA + b * weightB
    }

    /// Enables camera auto-follow and resets directional smoothing for a new target.
    func enableAutoFollow(for satelliteId: Int) {
        autoFollowSatelliteId = satelliteId
        isAutoFollowEnabled = true
        lastAutoFollowDirection = nil
        needsFollowCameraReacquire = false
        cameraFollowDisplayLink?.isPaused = false
    }

    /// Stops camera auto-follow and clears pending focus intent.
    func disableAutoFollow() {
        autoFollowSatelliteId = nil
        isAutoFollowEnabled = false
        lastAutoFollowDirection = nil
        pendingFocusRequest = nil
        needsFollowCameraReacquire = false
        cameraFollowDisplayLink?.isPaused = true
    }

    /// Animates the camera to look at a specific direction on the globe.
    ///
    /// The camera travels along an arc around the Earth rather than through it,
    /// using spherical linear interpolation (slerp) to maintain constant distance.
    /// For satellites on opposite sides, we pick a consistent intermediate path.
    private func animateCameraOrbit(
        to targetDirection: simd_float3,
        distance: Float,
        node: SCNNode,
        startDirection: simd_float3? = nil,
        startDistance: Float? = nil
    ) {
        GlobeCameraOrbitAnimator.animateCameraOrbit(
            to: targetDirection,
            distance: distance,
            node: node,
            maxPitchRadians: GlobeSceneView.maxCameraPitchAngleRadians,
            actionKey: cameraFocusActionKey,
            startDirection: startDirection,
            startDistance: startDistance
        )
    }

    /// Handles taps by hit-testing SceneKit nodes.
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = view else { return }
        let point = gesture.location(in: view)
        let hits = view.hitTest(point, options: [
            SCNHitTestOption.categoryBitMask: satelliteCategoryMask
        ])
        guard let selectedHit = hits.first(where: { !isSelectionIndicatorNode($0.node) }),
              let satelliteId = resolveSatelliteId(from: selectedHit.node) else {
            disableAutoFollow()
            onSelect(nil)
            return
        }

        // Match the TLE/Tracking path: queue a focus request, then enable follow
        // once the camera has started moving onto the selected target.
        view.defaultCameraController.stopInertia()
        suspendAutoFollow()
        if let scene = view.scene,
           let cameraNode = managedCameraNode(in: scene) {
            // Drop any previous focus action so the new selection does not chain
            // through an old target before moving to the newly tapped satellite.
            cameraNode.removeAction(forKey: cameraFocusActionKey)
        }
        // Queue focus so globe taps use the exact same camera path as list selections.
        pendingFocusRequest = SatelliteFocusRequest(satelliteId: satelliteId, token: UUID())
        onSelect(satelliteId)
    }

    /// Ignores the visual selection halo during hit-testing so taps target satellites only.
    private func isSelectionIndicatorNode(_ node: SCNNode) -> Bool {
        guard let indicator = selectionIndicatorNode else { return false }
        var current: SCNNode? = node
        while let candidate = current {
            if candidate === indicator {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    /// Resets the camera to the home position (0,0 over Africa) on double-tap.
    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = view,
              let scene = view.scene else { return }

        guard let cameraNode = prepareManagedCameraForProgrammaticMotion(in: scene) else { return }
        view.defaultCameraController.target = SCNVector3Zero

        disableAutoFollow()
        cameraNode.removeAction(forKey: cameraFocusActionKey)

        // Use the same orbit animation to smoothly return to the home position.
        let homeDirection = simd_normalize(simd_float3(homeCameraPosition.x, homeCameraPosition.y, homeCameraPosition.z))
        let homeDistance = simd_length(simd_float3(homeCameraPosition.x, homeCameraPosition.y, homeCameraPosition.z))

        animateCameraOrbit(
            to: homeDirection,
            distance: homeDistance,
            node: cameraNode
        )
    }

    /// Cancels any in-flight camera focus animation when the user starts dragging or zooming.
    @objc func handleInteraction(_ gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .began:
            activeCameraInteractionCount += 1
            if activeCameraInteractionCount == 1 {
                isCameraInteractionActive = true
                // Stop any one-shot focus animation so camera gestures feel immediate.
                if let scene = view?.scene {
                    managedCameraNode(in: scene)?.removeAction(forKey: cameraFocusActionKey)
                } else {
                    cameraNode?.removeAction(forKey: cameraFocusActionKey)
                }

                if let pan = gesture as? UIPanGestureRecognizer,
                   pan.numberOfTouches <= 1 {
                    // Dragging away from a target is treated as explicit deselection.
                    disableAutoFollow()
                    onSelect(nil)
                }
            }
        case .ended, .cancelled, .failed:
            activeCameraInteractionCount = max(0, activeCameraInteractionCount - 1)
            if activeCameraInteractionCount == 0 {
                isCameraInteractionActive = false
                if isAutoFollowEnabled {
                    needsFollowCameraReacquire = true
                }
            }
        default:
            break
        }
    }

    /// Allows our gesture recognizers to work alongside SceneKit's built-in camera gestures.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow all our gesture recognizers to fire alongside SceneKit's camera controller.
        return true
    }

    /// Ensures our tap/double-tap recognizers aren't blocked by SceneKit's internal gestures.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Let our own gestures fire without waiting on SceneKit's defaults.
        return false
    }

}
