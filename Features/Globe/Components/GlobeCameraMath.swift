//
//  GlobeCameraMath.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import Foundation
import simd

/// Pure math helpers used by `GlobeCameraController`.
///
/// Why this exists:
/// - Camera math is deterministic logic that benefits from isolated ownership.
/// - Pulling math out of the controller keeps state-machine code easier to scan.
///
/// What this does not do:
/// - It does not read or mutate SceneKit nodes.
/// - It does not decide camera modes or gesture ownership.
enum GlobeCameraMath {
    /// Clamps distance to configured safety limits.
    static func clampedDistance(
        _ value: Float,
        minimumDistance: Float,
        maximumDistance: Float
    ) -> Float {
        min(max(value, minimumDistance), maximumDistance)
    }

    /// Clamps camera pitch so orbit controls remain stable near the poles.
    static func clampedDirectionToVerticalLimits(
        _ direction: simd_float3,
        maxPitchRadians: Float,
        fallbackDirection: simd_float3
    ) -> simd_float3 {
        let length = simd_length(direction)
        guard length > 0.0001, length.isFinite else {
            return fallbackDirection
        }

        let normalized = direction / length
        guard normalized.x.isFinite, normalized.y.isFinite, normalized.z.isFinite else {
            return fallbackDirection
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
    static func smoothstep(_ value: Float) -> Float {
        let clamped = simd_clamp(value, 0, 1)
        return clamped * clamped * (3 - (2 * clamped))
    }

    /// Spherical interpolation between two normalized direction vectors.
    static func slerpDirection(
        from a: simd_float3,
        to b: simd_float3,
        t: Float,
        maxPitchRadians: Float,
        fallbackDirection: simd_float3
    ) -> simd_float3 {
        let clampedT = simd_clamp(t, 0, 1)
        let clampedDot = simd_clamp(simd_dot(a, b), -1, 1)
        let angle = acos(clampedDot)
        if angle < 0.001 {
            return b
        }

        let sinAngle = sin(angle)
        if abs(sinAngle) < 0.0001 {
            return clampedDirectionToVerticalLimits(
                simd_normalize(a * (1 - clampedT) + b * clampedT),
                maxPitchRadians: maxPitchRadians,
                fallbackDirection: fallbackDirection
            )
        }

        let weightA = sin((1 - clampedT) * angle) / sinAngle
        let weightB = sin(clampedT * angle) / sinAngle
        return clampedDirectionToVerticalLimits(
            (a * weightA) + (b * weightB),
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )
    }

    /// Applies yaw and pitch deltas to a direction vector.
    static func rotatedDirection(
        from direction: simd_float3,
        yawRadians: Float,
        pitchRadians: Float,
        maxPitchRadians: Float,
        fallbackDirection: simd_float3
    ) -> simd_float3 {
        let safeDirection = sanitizeDirection(
            direction,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        ) ?? fallbackDirection
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
        return clampedDirectionToVerticalLimits(
            nextDirection,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )
    }

    /// Sanitizes and normalizes direction vectors.
    static func sanitizeDirection(
        _ vector: simd_float3,
        maxPitchRadians: Float,
        fallbackDirection: simd_float3
    ) -> simd_float3? {
        let length = simd_length(vector)
        guard length.isFinite, length > 0.0001 else { return nil }
        let normalized = vector / length
        guard normalized.x.isFinite, normalized.y.isFinite, normalized.z.isFinite else { return nil }
        return clampedDirectionToVerticalLimits(
            normalized,
            maxPitchRadians: maxPitchRadians,
            fallbackDirection: fallbackDirection
        )
    }
}
