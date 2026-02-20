//
//  GlobeCameraTransitionMath.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import Foundation
import simd

/// Transition and follow interpolation helpers for `GlobeCameraController`.
///
/// These functions are pure and deterministic, which keeps state-machine code
/// focused on mode transitions rather than interpolation details.
enum GlobeCameraTransitionMath {
    /// Interpolated camera pose for a single transition frame.
    struct PoseFrame: Sendable {
        let direction: simd_float3
        let distance: Float
    }

    /// Computes one frame of transition motion for the current progress value.
    static func interpolatedPose(
        transition: GlobeCameraTransition,
        progress: Float,
        resolvedTargetDirection: simd_float3,
        minimumDistance: Float,
        maximumDistance: Float,
        maxPitchRadians: Float,
        fallbackDirection: simd_float3
    ) -> PoseFrame {
        let easedProgress = GlobeCameraMath.smoothstep(progress)
        let clampedStart = GlobeCameraMath.clampedDirectionToVerticalLimits(
            transition.startDirection,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )
        let clampedTarget = GlobeCameraMath.clampedDirectionToVerticalLimits(
            resolvedTargetDirection,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )

        if easedProgress < transition.rotationPhase {
            let rotationT = easedProgress / max(0.0001, transition.rotationPhase)
            return PoseFrame(
                direction: GlobeCameraMath.slerpDirection(
                    from: clampedStart,
                    to: clampedTarget,
                    t: rotationT,
                    maxPitchRadians: maxPitchRadians,
                    fallbackDirection: fallbackDirection
                ),
                distance: GlobeCameraMath.clampedDistance(
                    transition.startDistance,
                    minimumDistance: minimumDistance,
                    maximumDistance: maximumDistance
                )
            )
        }

        let zoomT = (easedProgress - transition.rotationPhase) / max(0.0001, 1 - transition.rotationPhase)
        let easedZoom = GlobeCameraMath.smoothstep(zoomT)
        let nextDistance = transition.startDistance
            + ((transition.targetDistance - transition.startDistance) * easedZoom)
        return PoseFrame(
            direction: clampedTarget,
            distance: GlobeCameraMath.clampedDistance(
                nextDistance,
                minimumDistance: minimumDistance,
                maximumDistance: maximumDistance
            )
        )
    }

    /// Builds a transition anchored to the current camera pose.
    static func makeTransition(
        kind: GlobeCameraTransition.Kind,
        startDirection: simd_float3,
        startDistance: Float,
        targetDirection: simd_float3,
        targetDistance: Float,
        minimumDistance: Float,
        maximumDistance: Float,
        maxPitchRadians: Float,
        fallbackDirection: simd_float3
    ) -> GlobeCameraTransition {
        let clampedTargetDirection = GlobeCameraMath.clampedDirectionToVerticalLimits(
            targetDirection,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )
        let clampedStartDirection = GlobeCameraMath.clampedDirectionToVerticalLimits(
            startDirection,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )
        let clampedStartDistance = GlobeCameraMath.clampedDistance(
            startDistance,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance
        )
        let clampedTargetDistance = GlobeCameraMath.clampedDistance(
            targetDistance,
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance
        )

        let angle = acos(simd_clamp(simd_dot(clampedStartDirection, clampedTargetDirection), -1, 1))
        let baseDuration: Float = angle > 2.6 ? 1.0 : 0.8
        let distanceDelta = abs(clampedTargetDistance - clampedStartDistance)
        let zoomDeltaDuration = min(0.55, distanceDelta * 0.24)
        let baseTransitionDuration = baseDuration + zoomDeltaDuration
        // Focus transitions intentionally run 40% longer to reduce perceived zoom snap.
        // Reset-home timing remains unchanged so double-tap recenters still feel responsive.
        let durationScale: Float = {
            switch kind {
            case .focus:
                return 1.4
            case .resetHome:
                return 1.0
            }
        }()

        return GlobeCameraTransition(
            kind: kind,
            startDirection: clampedStartDirection,
            startDistance: clampedStartDistance,
            targetDirection: clampedTargetDirection,
            targetDistance: clampedTargetDistance,
            duration: baseTransitionDuration * durationScale,
            rotationPhase: 0.9,
            elapsed: 0
        )
    }

    /// Computes one follow-step direction update for the provided frame delta.
    static func followDirection(
        currentDirection: simd_float3,
        targetDirection: simd_float3,
        frameDelta: Float,
        nominalFrameDelta: Float,
        maxPitchRadians: Float,
        fallbackDirection: simd_float3
    ) -> simd_float3 {
        let clampedDot = simd_clamp(simd_dot(currentDirection, targetDirection), -1, 1)
        let angularDelta = acos(clampedDot)
        if angularDelta < 0.00005 {
            return targetDirection
        }

        let frameScale = max(0.25, min(3.0, frameDelta / nominalFrameDelta))
        let baseT = max(0.08, min(0.35, angularDelta * 0.85))
        let interpolationT = max(0.08, min(0.55, baseT * frameScale))
        return GlobeCameraMath.slerpDirection(
            from: currentDirection,
            to: targetDirection,
            t: interpolationT,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )
    }
}
