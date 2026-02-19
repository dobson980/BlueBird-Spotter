//
//  GlobeCameraController.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/18/26.
//

import CoreGraphics
import Foundation
import SceneKit
import simd

/// Deterministic, single-owner camera state machine for the globe scene.
///
/// Why this exists:
/// - Selection, follow, and gesture interactions must use one source of truth.
/// - Mixing SceneKit camera controller state with custom camera animation caused
///   zoom snapback and unpredictable second-selection behavior.
///
/// What this does NOT do:
/// - It does not own gesture recognizers or hit-testing. The coordinator handles
///   UIKit events and forwards intent into this controller.
@MainActor
final class GlobeCameraController {
    /// Camera node driven by the state machine.
    private weak var cameraNode: SCNNode?
    /// Returns a scene-space direction vector for a satellite id.
    var satelliteDirectionProvider: ((Int) -> simd_float3?)?

    /// Current deterministic camera state.
    private(set) var state: GlobeCameraState

    /// Home direction used by double-tap reset.
    private let homeDirection: simd_float3
    /// Home camera distance used by double-tap reset.
    private let homeDistance: Float
    /// Selection zoom multiplier relative to home distance.
    private let selectionZoomMultiplier: Float
    /// Lower distance safety bound (keeps camera outside Earth).
    private let minimumDistance: Float
    /// Upper distance safety bound (keeps camera inside far plane).
    private let maximumDistance: Float
    /// Vertical pitch limit in radians.
    private let maxPitchRadians: Float

    /// Nominal frame delta for adaptive follow interpolation.
    private let nominalFrameDelta: Float = 1.0 / 60.0
    /// Horizontal pan sensitivity in radians per screen point.
    private let panYawRadiansPerPoint: Float = 0.006
    /// Vertical pan sensitivity in radians per screen point.
    private let panPitchRadiansPerPoint: Float = 0.004
    /// Last gesture-provided pinch scale sample.
    private var lastPinchScale: CGFloat?
    /// Rejects extreme one-event pinch spikes that can cause jumpy zoom.
    private let pinchScaleStepBounds: ClosedRange<Float> = 0.75...1.35

    init(
        homeCameraPosition: SCNVector3,
        selectionZoomMultiplier: Float,
        minimumFollowDistance: Float,
        maximumFollowDistance: Float,
        maxPitchRadians: Float
    ) {
        let homeVector = simd_float3(homeCameraPosition.x, homeCameraPosition.y, homeCameraPosition.z)
        let homeLength = simd_length(homeVector)
        let resolvedHomeDirection: simd_float3
        let resolvedHomeDistance: Float
        if homeLength.isFinite, homeLength > 0.001 {
            resolvedHomeDirection = homeVector / homeLength
            resolvedHomeDistance = homeLength
        } else {
            resolvedHomeDirection = simd_float3(0, 0, 1)
            resolvedHomeDistance = 3
        }

        self.homeDirection = resolvedHomeDirection
        self.homeDistance = resolvedHomeDistance
        self.selectionZoomMultiplier = selectionZoomMultiplier
        self.minimumDistance = minimumFollowDistance
        self.maximumDistance = maximumFollowDistance
        self.maxPitchRadians = maxPitchRadians
        self.state = GlobeCameraState(
            mode: .freeOrbit,
            direction: resolvedHomeDirection,
            distance: resolvedHomeDistance,
            selectedSatelliteId: nil,
            activeGesture: nil,
            transition: nil,
            lastFocusToken: nil
        )
    }

    /// Reports whether frame-by-frame updates are currently required.
    var requiresDisplayLinkUpdates: Bool {
        switch state.mode {
        case .freeOrbit:
            return false
        case .transitioning, .following, .resettingHome:
            return true
        }
    }

    /// Camera mode projection for diagnostics.
    var mode: GlobeCameraMode { state.mode }

    /// Current camera distance projection for diagnostics.
    var distance: Float { state.distance }

    /// Current follow target projection for diagnostics.
    var followSatelliteId: Int? { state.followSatelliteId }

    /// Binds the managed SceneKit camera node and synchronizes initial pose.
    func attachCameraNode(_ node: SCNNode) {
        // The state machine is the single source of truth after initial attach.
        // Re-syncing from SceneKit every frame can reintroduce stale-pose races,
        // especially during follow mode when display-link ticks are continuous.
        if cameraNode !== node {
            cameraNode = node
            syncStateFromNodePresentation(node)
        }
        applyCurrentPose()
    }

    /// Requests a focus transition to a satellite.
    ///
    /// Returns `true` when the request was accepted and a transition started.
    @discardableResult
    func requestFocus(satelliteId: Int, token: UUID) -> Bool {
        // Token dedupe prevents duplicate update cycles from restarting transitions.
        if state.lastFocusToken == token {
            return false
        }
        guard let targetDirection = satelliteDirection(for: satelliteId) else {
            return false
        }

        state.lastFocusToken = token
        state.selectedSatelliteId = satelliteId
        state.mode = .transitioning(toSatelliteId: satelliteId)
        state.transition = makeTransition(
            kind: .focus(satelliteId: satelliteId),
            targetDirection: targetDirection,
            targetDistance: selectionFocusDistance
        )
        applyCurrentPose()
        return true
    }

    /// Clears selection and stops follow/transition unless home-reset is in progress.
    func clearSelection(preserveResetTransition: Bool = false) {
        state.selectedSatelliteId = nil
        lastPinchScale = nil
        if preserveResetTransition, case .resettingHome = state.mode {
            return
        }
        state.transition = nil
        state.mode = .freeOrbit
    }

    /// Starts a smooth transition back to the home camera pose.
    func requestResetHome() {
        state.selectedSatelliteId = nil
        state.transition = makeTransition(
            kind: .resetHome,
            targetDirection: homeDirection,
            targetDistance: homeDistance
        )
        state.mode = .resettingHome
        applyCurrentPose()
    }

    /// Marks pan gesture ownership and cancels one-shot transitions.
    func beginPan() {
        state.activeGesture = .pan
        cancelTransitionForUserGestureIfNeeded()
    }

    /// Applies a pan delta and optionally deselects when drag exceeds threshold.
    ///
    /// Returns `true` when this update deselected the current satellite.
    @discardableResult
    func updatePan(
        delta: CGPoint,
        totalTranslation: CGPoint,
        deselectThreshold: CGFloat
    ) -> Bool {
        if state.activeGesture != .pan {
            beginPan()
        }

        let translationMagnitude = hypot(totalTranslation.x, totalTranslation.y)
        var didDeselect = false
        if state.selectedSatelliteId != nil, translationMagnitude > deselectThreshold {
            clearSelection()
            didDeselect = true
        } else if state.selectedSatelliteId != nil {
            // Keep tiny drags from accidentally moving the camera while still selected.
            return false
        }

        let deltaX = Float(delta.x)
        let deltaY = Float(delta.y)
        guard deltaX.isFinite, deltaY.isFinite else {
            return didDeselect
        }

        let yaw = -deltaX * panYawRadiansPerPoint
        let pitch = -deltaY * panPitchRadiansPerPoint
        state.direction = GlobeCameraMath.rotatedDirection(
            from: state.direction,
            yawRadians: yaw,
            pitchRadians: pitch,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: homeDirection
        )
        applyCurrentPose()
        return didDeselect
    }

    /// Ends pan gesture ownership.
    func endPan() {
        if state.activeGesture == .pan {
            state.activeGesture = nil
        }
    }

    /// Marks pinch gesture ownership and captures current distance baseline.
    func beginPinch() {
        state.activeGesture = .pinch
        lastPinchScale = 1
        cancelTransitionForUserGestureIfNeeded()
    }

    /// Applies pinch zoom while preserving current selection/follow intent.
    func updatePinch(scale: CGFloat) {
        if state.activeGesture != .pinch {
            beginPinch()
        }
        guard scale.isFinite, scale > 0 else { return }

        // Use relative scale deltas so each event contributes incrementally.
        // This avoids large absolute-scale jumps when recognizer state jitters.
        let previousScale = lastPinchScale ?? scale
        let rawScaleStep = Float(scale / previousScale)
        guard rawScaleStep.isFinite, rawScaleStep > 0 else { return }
        lastPinchScale = scale

        // Bound single-event spikes while preserving direct pinch response.
        let boundedScaleStep = simd_clamp(
            rawScaleStep,
            pinchScaleStepBounds.lowerBound,
            pinchScaleStepBounds.upperBound
        )
        let targetDistance = GlobeCameraMath.clampedDistance(
            state.distance / boundedScaleStep,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance
        )
        state.distance = targetDistance
        applyCurrentPose()
    }

    /// Ends pinch gesture ownership.
    func endPinch() {
        if state.activeGesture == .pinch {
            state.activeGesture = nil
        }
        lastPinchScale = nil
    }

    /// Advances transition/follow behavior by one frame.
    func tick(frameDelta: Float) {
        let safeDelta = max(0.001, min(0.1, frameDelta.isFinite ? frameDelta : nominalFrameDelta))

        switch state.mode {
        case .transitioning:
            advanceTransition(frameDelta: safeDelta)
        case .following:
            advanceFollow(frameDelta: safeDelta)
        case .resettingHome:
            advanceTransition(frameDelta: safeDelta)
        case .freeOrbit:
            break
        }

        applyCurrentPose()
    }

    /// Advances the active transition by one frame.
    private func advanceTransition(frameDelta: Float) {
        guard var transition = state.transition else {
            switch state.mode {
            case .transitioning(let satelliteId):
                state.mode = .following(satelliteId: satelliteId)
            case .resettingHome:
                state.mode = .freeOrbit
            case .freeOrbit, .following:
                break
            }
            return
        }

        transition.elapsed += frameDelta
        let progress = transition.transitionProgress
        let resolvedTargetDirection = transitionTargetDirection(for: transition)
        let frame = GlobeCameraTransitionMath.interpolatedPose(
            transition: transition,
            progress: progress,
            resolvedTargetDirection: resolvedTargetDirection,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: homeDirection
        )
        state.direction = frame.direction
        state.distance = frame.distance

        if progress >= 1 {
            state.transition = nil
            switch transition.kind {
            case .focus(let satelliteId):
                if satelliteDirection(for: satelliteId) != nil {
                    state.mode = .following(satelliteId: satelliteId)
                } else {
                    // If the satellite is unavailable, fall back to free orbit.
                    state.selectedSatelliteId = nil
                    state.mode = .freeOrbit
                }
            case .resetHome:
                state.mode = .freeOrbit
            }
        } else {
            state.transition = transition
        }
    }

    /// Applies per-frame directional follow while preserving user-selected distance.
    private func advanceFollow(frameDelta: Float) {
        guard case .following(let satelliteId) = state.mode else { return }
        guard let targetDirection = satelliteDirection(for: satelliteId) else {
            clearSelection()
            return
        }

        state.direction = GlobeCameraTransitionMath.followDirection(
            currentDirection: state.direction,
            targetDirection: targetDirection,
            frameDelta: frameDelta,
            nominalFrameDelta: nominalFrameDelta,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: homeDirection
        )
        state.distance = GlobeCameraMath.clampedDistance(
            state.distance,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance
        )
    }

    /// Builds a new transition anchored to the current camera pose.
    private func makeTransition(
        kind: GlobeCameraTransition.Kind,
        targetDirection: simd_float3,
        targetDistance: Float
    ) -> GlobeCameraTransition {
        GlobeCameraTransitionMath.makeTransition(
            kind: kind,
            startDirection: state.direction,
            startDistance: state.distance,
            targetDirection: targetDirection,
            targetDistance: targetDistance,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: homeDirection
        )
    }

    /// Resolves target direction for a transition, refreshing live satellite focus when possible.
    private func transitionTargetDirection(for transition: GlobeCameraTransition) -> simd_float3 {
        switch transition.kind {
        case .focus(let satelliteId):
            return satelliteDirection(for: satelliteId) ?? transition.targetDirection
        case .resetHome:
            return transition.targetDirection
        }
    }

    /// Cancels one-shot transitions when the user explicitly starts a gesture.
    private func cancelTransitionForUserGestureIfNeeded() {
        switch state.mode {
        case .transitioning(let transitionSatelliteId):
            state.transition = nil
            let selectedSatelliteId = state.selectedSatelliteId ?? transitionSatelliteId
            state.mode = .following(satelliteId: selectedSatelliteId)
        case .resettingHome:
            state.transition = nil
            state.mode = .freeOrbit
        case .freeOrbit, .following:
            break
        }
    }

    /// Reads the rendered camera pose so state starts from what users currently see.
    private func syncStateFromNodePresentation(_ node: SCNNode) {
        let position = node.presentation.position
        let vector = simd_float3(position.x, position.y, position.z)
        let length = simd_length(vector)
        guard length.isFinite, length > 0.001 else { return }
        state.direction = GlobeCameraMath.clampedDirectionToVerticalLimits(
            vector / length,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: homeDirection
        )
        state.distance = GlobeCameraMath.clampedDistance(
            length,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance
        )
    }

    /// Writes the current state pose into the managed camera node.
    private func applyCurrentPose() {
        guard let cameraNode else { return }
        let clampedDirection = GlobeCameraMath.clampedDirectionToVerticalLimits(
            state.direction,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: homeDirection
        )
        let clampedDistance = GlobeCameraMath.clampedDistance(
            state.distance,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance
        )
        let position = clampedDirection * clampedDistance

        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return }
        state.direction = clampedDirection
        state.distance = clampedDistance
        orientCameraNodeTowardOrigin(cameraNode, position: position)
    }

    /// Applies a camera transform that always keeps world-up aligned.
    ///
    /// Using an explicit basis avoids roll flips that can make Earth appear upside down.
    private func orientCameraNodeTowardOrigin(_ node: SCNNode, position: simd_float3) {
        node.simdTransform = GlobeCameraPoseWriter.makeTransform(lookingAtOriginFrom: position)
    }

    /// Converts a satellite id into a normalized scene-space direction.
    private func satelliteDirection(for satelliteId: Int) -> simd_float3? {
        guard let rawDirection = satelliteDirectionProvider?(satelliteId) else {
            return nil
        }
        return GlobeCameraMath.sanitizeDirection(
            rawDirection,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: homeDirection
        )
    }

    /// Computes the entry zoom used when focus transition begins.
    private var selectionFocusDistance: Float {
        GlobeCameraMath.clampedDistance(
            max(0.6, homeDistance * selectionZoomMultiplier),
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance
        )
    }
}
