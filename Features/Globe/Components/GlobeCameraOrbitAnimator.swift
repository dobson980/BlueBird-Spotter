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
        actionKey: String,
        startDirection: simd_float3? = nil,
        startDistance: Float? = nil
    ) {
        // Clamp the target direction so camera controls remain stable near the poles.
        let clampedDirection = clampDirectionToVerticalLimits(targetDirection, maxPitch: maxPitchRadians)

        guard clampedDirection.x.isFinite, clampedDirection.y.isFinite, clampedDirection.z.isFinite else {
            return
        }

        let resolvedStartDirection: simd_float3
        let resolvedStartDistance: Float
        if let providedStartDirection = startDirection,
           let providedStartDistance = startDistance,
           providedStartDistance.isFinite,
           providedStartDistance > 0.001 {
            let normalizedStartDirection = simd_normalize(providedStartDirection)
            if normalizedStartDirection.x.isFinite,
               normalizedStartDirection.y.isFinite,
               normalizedStartDirection.z.isFinite {
                resolvedStartDirection = normalizedStartDirection
                resolvedStartDistance = providedStartDistance
            } else {
                // Fallback to rendered presentation space so chained requests
                // begin from what is visibly on-screen.
                let presentationPosition = node.presentation.position
                let startPos = simd_float3(
                    presentationPosition.x.isFinite ? presentationPosition.x : 0,
                    presentationPosition.y.isFinite ? presentationPosition.y : 0,
                    presentationPosition.z.isFinite ? presentationPosition.z : 3.0
                )
                let startLength = simd_length(startPos)
                if startLength > 0.001 {
                    resolvedStartDirection = startPos / startLength
                    resolvedStartDistance = startLength
                } else {
                    resolvedStartDirection = simd_float3(0, 0, 1)
                    resolvedStartDistance = distance
                }
            }
        } else {
            // Use rendered presentation space so chained requests start from
            // the camera pose currently visible on-screen.
            let presentationPosition = node.presentation.position
            let startPos = simd_float3(
                presentationPosition.x.isFinite ? presentationPosition.x : 0,
                presentationPosition.y.isFinite ? presentationPosition.y : 0,
                presentationPosition.z.isFinite ? presentationPosition.z : 3.0
            )
            let startLength = simd_length(startPos)
            if startLength > 0.001 {
                resolvedStartDirection = startPos / startLength
                resolvedStartDistance = startLength
            } else {
                resolvedStartDirection = simd_float3(0, 0, 1)
                resolvedStartDistance = distance
            }
        }

        let dot = simd_clamp(simd_dot(resolvedStartDirection, clampedDirection), -1.0, 1.0)
        let angle = acos(dot)

        // Near-opposite directions need an intermediate waypoint to avoid path ambiguity.
        let needsIntermediate = angle > 2.6 // ~150 degrees
        let intermediateDirection: simd_float3
        if needsIntermediate {
            let yUp = simd_float3(0, 1, 0)
            var perp = simd_cross(resolvedStartDirection, yUp)
            let perpLen = simd_length(perp)
            if perpLen > 0.001 {
                perp = perp / perpLen
            } else {
                perp = simd_float3(0, 0, 1)
            }
            let midY = (resolvedStartDirection.y + clampedDirection.y) * 0.5
            let horizontalScale = sqrt(max(0.01, 1.0 - midY * midY))
            intermediateDirection = simd_normalize(simd_float3(perp.x * horizontalScale, midY, perp.z * horizontalScale))
        } else {
            intermediateDirection = simd_float3(0, 0, 0)
        }

        node.removeAction(forKey: actionKey)

        // Two-phase focus: rotate onto the target first, then ease into target zoom.
        // Extend duration slightly when the requested zoom delta is large so the
        // motion reads as "pan then zoom" instead of an abrupt zoom-pop.
        let distanceDelta = abs(distance - resolvedStartDistance)
        let zoomDeltaDuration = min(0.55, TimeInterval(distanceDelta * 0.24))
        let baseDuration: TimeInterval = needsIntermediate ? 1.0 : 0.8
        let duration = baseDuration + zoomDeltaDuration
        let rotationPhase: Float = 0.9
        let action = SCNAction.customAction(duration: duration) {
            [resolvedStartDirection, clampedDirection, intermediateDirection, needsIntermediate, resolvedStartDistance, distance] actionNode, time in
            let t = Float(time / CGFloat(duration))
            let easedT = t * t * (3.0 - 2.0 * t)

            let interpolatedDirection: simd_float3
            let interpolatedDistance: Float
            if easedT < rotationPhase {
                // Phase 1: move around the globe at the current zoom level.
                let rotationT = easedT / rotationPhase
                if needsIntermediate {
                    if rotationT < 0.5 {
                        let segmentT = rotationT * 2.0
                        interpolatedDirection = slerp(from: resolvedStartDirection, to: intermediateDirection, t: segmentT)
                    } else {
                        let segmentT = (rotationT - 0.5) * 2.0
                        interpolatedDirection = slerp(from: intermediateDirection, to: clampedDirection, t: segmentT)
                    }
                } else {
                    interpolatedDirection = slerp(from: resolvedStartDirection, to: clampedDirection, t: rotationT)
                }
                interpolatedDistance = resolvedStartDistance
            } else {
                // Phase 2: keep target centered and zoom to selection distance.
                let zoomT = (easedT - rotationPhase) / max(0.0001, 1.0 - rotationPhase)
                let easedZoomT = zoomT * zoomT * (3.0 - 2.0 * zoomT)
                interpolatedDirection = clampedDirection
                interpolatedDistance = resolvedStartDistance + ((distance - resolvedStartDistance) * easedZoomT)
            }

            let x = interpolatedDirection.x * interpolatedDistance
            let y = interpolatedDirection.y * interpolatedDistance
            let z = interpolatedDirection.z * interpolatedDistance

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
