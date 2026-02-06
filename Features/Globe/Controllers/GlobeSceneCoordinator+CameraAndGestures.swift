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
        tracked _: [TrackedSatellite],
        in scene: SCNScene
    ) {
        if let request, lastFocusToken != request.token {
            lastFocusToken = request.token
            pendingFocusRequest = request
        }

        guard let pending = pendingFocusRequest else { return }
        guard let targetNode = satelliteNodes[pending.satelliteId] else { return }

        // Ensure we have the camera node reference.
        if cameraNode == nil {
            cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
        }
        guard let cameraNode = cameraNode else { return }
        view?.pointOfView = cameraNode

        // Get the direction from Earth's center to the satellite.
        let satellitePosition = targetNode.position
        let posX = satellitePosition.x
        let posY = satellitePosition.y
        let posZ = satellitePosition.z

        // Validate position is not NaN or zero.
        guard posX.isFinite && posY.isFinite && posZ.isFinite else {
            pendingFocusRequest = nil
            return
        }

        let directionLength = sqrt(posX * posX + posY * posY + posZ * posZ)
        guard directionLength > 0.001 else {
            pendingFocusRequest = nil
            return
        }

        // Normalize to get direction from Earth center toward satellite.
        let targetDirection = simd_float3(
            posX / directionLength,
            posY / directionLength,
            posZ / directionLength
        )

        // Position camera at the same distance as home position.
        let desiredDistance: Float = 3.0

        animateCameraOrbit(
            to: targetDirection,
            distance: desiredDistance,
            node: cameraNode
        )

        pendingFocusRequest = nil
    }

    /// Animates the camera to look at a specific direction on the globe.
    ///
    /// The camera travels along an arc around the Earth rather than through it,
    /// using spherical linear interpolation (slerp) to maintain constant distance.
    /// For satellites on opposite sides, we pick a consistent intermediate path.
    private func animateCameraOrbit(
        to targetDirection: simd_float3,
        distance: Float,
        node: SCNNode
    ) {
        GlobeCameraOrbitAnimator.animateCameraOrbit(
            to: targetDirection,
            distance: distance,
            node: node,
            maxPitchRadians: GlobeSceneView.maxCameraPitchAngleRadians,
            actionKey: cameraFocusActionKey
        )
    }

    /// Handles taps by hit-testing SceneKit nodes.
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = view else { return }
        let point = gesture.location(in: view)
        let hits = view.hitTest(point, options: [
            SCNHitTestOption.categoryBitMask: satelliteCategoryMask
        ])
        guard let hitNode = hits.first?.node else {
            onSelect(nil)
            return
        }

        onSelect(resolveSatelliteId(from: hitNode))
    }

    /// Resets the camera to the home position (0,0 over Africa) on double-tap.
    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = view,
              let scene = view.scene else { return }

        // Ensure we have the camera node reference.
        if cameraNode == nil {
            cameraNode = scene.rootNode.childNode(withName: "globeCamera", recursively: false)
        }
        guard let cameraNode = cameraNode else { return }
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3Zero

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
        if gesture.state == .began {
            // Stop the focus animation so it doesn't fight with the user's gesture.
            cameraNode?.removeAction(forKey: cameraFocusActionKey)
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
