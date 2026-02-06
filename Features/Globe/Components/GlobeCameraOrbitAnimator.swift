//
//  GlobeCameraOrbitAnimator.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import Foundation
import SceneKit
import simd

/// Encapsulates camera-orbit interpolation logic for the globe experience.
///
/// This helper keeps camera math separate from the SceneKit coordinator so the
/// main rendering type can focus on state updates and event orchestration.
enum GlobeCameraOrbitAnimator {
    /// Animates the camera to look at a specific direction on the globe.
    ///
    /// The camera travels along an arc around Earth (instead of cutting through it),
    /// which makes focus transitions predictable and easier to follow visually.
    nonisolated static func animateCameraOrbit(
        to targetDirection: simd_float3,
        distance: Float,
        node: SCNNode,
        maxPitchRadians: Float,
        actionKey: String
    ) {
        // Clamp the target direction so camera controls remain stable near the poles.
        let clampedDirection = clampDirectionToVerticalLimits(targetDirection, maxPitch: maxPitchRadians)

        guard clampedDirection.x.isFinite, clampedDirection.y.isFinite, clampedDirection.z.isFinite else {
            return
        }

        let startX = node.position.x
        let startY = node.position.y
        let startZ = node.position.z

        // If SceneKit gives us an invalid start position, fall back to home distance.
        let safeStartX = startX.isFinite ? startX : 0
        let safeStartY = startY.isFinite ? startY : 0
        let safeStartZ = startZ.isFinite ? startZ : 3.0

        let startPos = simd_float3(safeStartX, safeStartY, safeStartZ)
        let startLength = simd_length(startPos)
        let startDirection: simd_float3
        if startLength > 0.001 {
            startDirection = startPos / startLength
        } else {
            startDirection = simd_float3(0, 0, 1)
        }

        let dot = simd_clamp(simd_dot(startDirection, clampedDirection), -1.0, 1.0)
        let angle = acos(dot)

        // Near-opposite directions need an intermediate waypoint to avoid path ambiguity.
        let needsIntermediate = angle > 2.6 // ~150 degrees
        let intermediateDirection: simd_float3
        if needsIntermediate {
            let yUp = simd_float3(0, 1, 0)
            var perp = simd_cross(startDirection, yUp)
            let perpLen = simd_length(perp)
            if perpLen > 0.001 {
                perp = perp / perpLen
            } else {
                perp = simd_float3(0, 0, 1)
            }
            let midY = (startDirection.y + clampedDirection.y) * 0.5
            let horizontalScale = sqrt(max(0.01, 1.0 - midY * midY))
            intermediateDirection = simd_normalize(simd_float3(perp.x * horizontalScale, midY, perp.z * horizontalScale))
        } else {
            intermediateDirection = simd_float3(0, 0, 0)
        }

        node.removeAction(forKey: actionKey)

        let duration: TimeInterval = needsIntermediate ? 0.6 : 0.45
        let action = SCNAction.customAction(duration: duration) {
            [startDirection, clampedDirection, intermediateDirection, needsIntermediate, distance] actionNode, time in
            let t = Float(time / CGFloat(duration))
            let easedT = t * t * (3.0 - 2.0 * t)

            let interpolatedDirection: simd_float3
            if needsIntermediate {
                if easedT < 0.5 {
                    let segmentT = easedT * 2.0
                    interpolatedDirection = slerp(from: startDirection, to: intermediateDirection, t: segmentT)
                } else {
                    let segmentT = (easedT - 0.5) * 2.0
                    interpolatedDirection = slerp(from: intermediateDirection, to: clampedDirection, t: segmentT)
                }
            } else {
                interpolatedDirection = slerp(from: startDirection, to: clampedDirection, t: easedT)
            }

            let x = interpolatedDirection.x * distance
            let y = interpolatedDirection.y * distance
            let z = interpolatedDirection.z * distance

            if x.isFinite, y.isFinite, z.isFinite {
                actionNode.position = SCNVector3(x, y, z)
                orientCameraTowardOrigin(actionNode)
            }
        }
        node.runAction(action, forKey: actionKey)
    }

    /// Spherical linear interpolation between two unit vectors.
    nonisolated private static func slerp(from a: simd_float3, to b: simd_float3, t: Float) -> simd_float3 {
        let dot = simd_clamp(simd_dot(a, b), -1.0, 1.0)
        let angle = acos(dot)

        if angle < 0.001 {
            return b
        }

        let sinAngle = sin(angle)
        let weightA = sin((1.0 - t) * angle) / sinAngle
        let weightB = sin(t * angle) / sinAngle
        return a * weightA + b * weightB
    }

    /// Points the camera at the origin while keeping Y as the up direction.
    nonisolated private static func orientCameraTowardOrigin(_ node: SCNNode) {
        let position = node.position
        let forward = simd_normalize(simd_float3(-position.x, -position.y, -position.z))

        let worldUp = simd_float3(0, 1, 0)

        var right = simd_cross(forward, worldUp)
        let rightLen = simd_length(right)
        if rightLen > 0.001 {
            right = right / rightLen
        } else {
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

    /// Clamps a direction vector to avoid unstable turntable behavior at the poles.
    nonisolated private static func clampDirectionToVerticalLimits(
        _ direction: simd_float3,
        maxPitch: Float
    ) -> simd_float3 {
        let length = simd_length(direction)
        guard length > 0.0001, length.isFinite else {
            return simd_float3(0, 0, 1)
        }

        let normalized = direction / length

        guard normalized.x.isFinite, normalized.y.isFinite, normalized.z.isFinite else {
            return simd_float3(0, 0, 1)
        }

        let maxY = sin(maxPitch)
        let clampedY = max(-maxY, min(maxY, normalized.y))

        let horizontalScale = sqrt(max(0, 1 - clampedY * clampedY))
        let originalHorizontal = simd_float2(normalized.x, normalized.z)
        let originalHorizontalLength = simd_length(originalHorizontal)

        let clampedHorizontal: simd_float2
        if originalHorizontalLength > 0.0001 {
            clampedHorizontal = (originalHorizontal / originalHorizontalLength) * horizontalScale
        } else {
            clampedHorizontal = simd_float2(0, horizontalScale)
        }

        let result = simd_float3(clampedHorizontal.x, clampedY, clampedHorizontal.y)

        let resultLength = simd_length(result)
        if resultLength > 0.99,
           resultLength < 1.01,
           result.x.isFinite,
           result.y.isFinite,
           result.z.isFinite {
            return result
        }

        return simd_float3(0, 0, 1)
    }
}
