//
//  GlobeCameraController.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
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
        state.direction = rotatedDirection(
            from: state.direction,
            yawRadians: yaw,
            pitchRadians: pitch
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
        let targetDistance = clampedDistance(state.distance / boundedScaleStep)
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
        let easedProgress = smoothstep(progress)

        let resolvedTargetDirection = transitionTargetDirection(for: transition)
        let clampedStart = clampedDirectionToVerticalLimits(transition.startDirection)
        let clampedTarget = clampedDirectionToVerticalLimits(resolvedTargetDirection)

        if easedProgress < transition.rotationPhase {
            // Phase 1: orbit to target while preserving current zoom.
            let rotationT = easedProgress / max(0.0001, transition.rotationPhase)
            state.direction = slerpDirection(from: clampedStart, to: clampedTarget, t: rotationT)
            state.distance = clampedDistance(transition.startDistance)
        } else {
            // Phase 2: keep target centered and blend only distance.
            let zoomT = (easedProgress - transition.rotationPhase) / max(0.0001, 1 - transition.rotationPhase)
            let easedZoom = smoothstep(zoomT)
            state.direction = clampedTarget
            let nextDistance = transition.startDistance
                + ((transition.targetDistance - transition.startDistance) * easedZoom)
            state.distance = clampedDistance(nextDistance)
        }

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

        let currentDirection = state.direction
        let clampedDot = simd_clamp(simd_dot(currentDirection, targetDirection), -1, 1)
        let angularDelta = acos(clampedDot)
        if angularDelta < 0.00005 {
            state.direction = targetDirection
            state.distance = clampedDistance(state.distance)
            return
        }

        // Adaptive blend keeps lock-on stable for both slow drift and fast passes.
        let frameScale = max(0.25, min(3.0, frameDelta / nominalFrameDelta))
        let baseT = max(0.08, min(0.35, angularDelta * 0.85))
        let interpolationT = max(0.08, min(0.55, baseT * frameScale))
        state.direction = slerpDirection(from: currentDirection, to: targetDirection, t: interpolationT)
        state.distance = clampedDistance(state.distance)
    }

    /// Builds a new transition anchored to the current camera pose.
    private func makeTransition(
        kind: GlobeCameraTransition.Kind,
        targetDirection: simd_float3,
        targetDistance: Float
    ) -> GlobeCameraTransition {
        let clampedTargetDirection = clampedDirectionToVerticalLimits(targetDirection)
        let startDirection = clampedDirectionToVerticalLimits(state.direction)
        let startDistance = clampedDistance(state.distance)
        let clampedTargetDistance = clampedDistance(targetDistance)

        let angle = acos(simd_clamp(simd_dot(startDirection, clampedTargetDirection), -1, 1))
        let baseDuration: Float = angle > 2.6 ? 1.0 : 0.8
        let distanceDelta = abs(clampedTargetDistance - startDistance)
        let zoomDeltaDuration = min(0.55, distanceDelta * 0.24)

        return GlobeCameraTransition(
            kind: kind,
            startDirection: startDirection,
            startDistance: startDistance,
            targetDirection: clampedTargetDirection,
            targetDistance: clampedTargetDistance,
            duration: baseDuration + zoomDeltaDuration,
            rotationPhase: 0.9,
            elapsed: 0
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
        state.direction = clampedDirectionToVerticalLimits(vector / length)
        state.distance = clampedDistance(length)
    }

    /// Writes the current state pose into the managed camera node.
    private func applyCurrentPose() {
        guard let cameraNode else { return }
        let clampedDirection = clampedDirectionToVerticalLimits(state.direction)
        let clampedDistance = clampedDistance(state.distance)
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
        let forward = simd_normalize(-position)
        let worldUp = simd_float3(0, 1, 0)

        var right = simd_cross(forward, worldUp)
        let rightLength = simd_length(right)
        if rightLength > 0.001 {
            right /= rightLength
        } else {
            // Near-pole fallback keeps a stable right axis.
            right = simd_float3(1, 0, 0)
        }

        let up = simd_cross(right, forward)
        let rotationMatrix = simd_float4x4(columns: (
            simd_float4(right.x, right.y, right.z, 0),
            simd_float4(up.x, up.y, up.z, 0),
            simd_float4(-forward.x, -forward.y, -forward.z, 0),
            simd_float4(0, 0, 0, 1)
        ))

        node.simdTransform = simd_float4x4(columns: (
            rotationMatrix.columns.0,
            rotationMatrix.columns.1,
            rotationMatrix.columns.2,
            simd_float4(position.x, position.y, position.z, 1)
        ))
    }

    /// Converts a satellite id into a normalized scene-space direction.
    private func satelliteDirection(for satelliteId: Int) -> simd_float3? {
        guard let rawDirection = satelliteDirectionProvider?(satelliteId) else {
            return nil
        }
        return sanitizeDirection(rawDirection)
    }

    /// Applies yaw and pitch deltas to a direction vector.
    private func rotatedDirection(
        from direction: simd_float3,
        yawRadians: Float,
        pitchRadians: Float
    ) -> simd_float3 {
        let safeDirection = sanitizeDirection(direction) ?? homeDirection
        let yawRotation = simd_quatf(angle: yawRadians, axis: simd_float3(0, 1, 0))
        var nextDirection = yawRotation.act(safeDirection)

        // Pitch around camera-right so vertical drag feels natural from any longitude.
        var rightAxis = simd_cross(simd_float3(0, 1, 0), nextDirection)
        let rightLength = simd_length(rightAxis)
        if rightLength > 0.0001 {
            rightAxis /= rightLength
        } else {
            rightAxis = simd_float3(1, 0, 0)
        }
        let pitchRotation = simd_quatf(angle: pitchRadians, axis: rightAxis)
        nextDirection = pitchRotation.act(nextDirection)
        return clampedDirectionToVerticalLimits(nextDirection)
    }

    /// Clamps distance to configured safety limits.
    private func clampedDistance(_ value: Float) -> Float {
        min(max(value, minimumDistance), maximumDistance)
    }

    /// Computes the entry zoom used when focus transition begins.
    private var selectionFocusDistance: Float {
        clampedDistance(max(0.6, homeDistance * selectionZoomMultiplier))
    }

    /// Sanitizes and normalizes direction vectors.
    private func sanitizeDirection(_ vector: simd_float3) -> simd_float3? {
        let length = simd_length(vector)
        guard length.isFinite, length > 0.0001 else { return nil }
        let normalized = vector / length
        guard normalized.x.isFinite, normalized.y.isFinite, normalized.z.isFinite else { return nil }
        return clampedDirectionToVerticalLimits(normalized)
    }

    /// Clamps camera pitch so orbit controls remain stable near the poles.
    private func clampedDirectionToVerticalLimits(_ direction: simd_float3) -> simd_float3 {
        let length = simd_length(direction)
        guard length > 0.0001, length.isFinite else {
            return homeDirection
        }

        let normalized = direction / length
        guard normalized.x.isFinite, normalized.y.isFinite, normalized.z.isFinite else {
            return homeDirection
        }

        let maxY = sin(maxPitchRadians)
        let clampedY = max(-maxY, min(maxY, normalized.y))
        let horizontal = simd_float2(normalized.x, normalized.z)
        let horizontalLength = simd_length(horizontal)
        let horizontalScale = sqrt(max(0.01, 1 - (clampedY * clampedY)))

        let clampedHorizontal: simd_float2
        if horizontalLength > 0.0001 {
            clampedHorizontal = (horizontal / horizontalLength) * horizontalScale
        } else {
            clampedHorizontal = simd_float2(0, horizontalScale)
        }

        return simd_float3(clampedHorizontal.x, clampedY, clampedHorizontal.y)
    }

    /// Smoothstep easing for perceptually stable motion.
    private func smoothstep(_ value: Float) -> Float {
        let clamped = simd_clamp(value, 0, 1)
        return clamped * clamped * (3 - (2 * clamped))
    }

    /// Spherical interpolation between two normalized direction vectors.
    private func slerpDirection(from a: simd_float3, to b: simd_float3, t: Float) -> simd_float3 {
        let clampedT = simd_clamp(t, 0, 1)
        let clampedDot = simd_clamp(simd_dot(a, b), -1, 1)
        let angle = acos(clampedDot)
        if angle < 0.001 {
            return b
        }

        let sinAngle = sin(angle)
        if abs(sinAngle) < 0.0001 {
            return clampedDirectionToVerticalLimits(simd_normalize(a * (1 - clampedT) + b * clampedT))
        }

        let weightA = sin((1 - clampedT) * angle) / sinAngle
        let weightB = sin(clampedT * angle) / sinAngle
        return clampedDirectionToVerticalLimits((a * weightA) + (b * weightB))
    }
}
