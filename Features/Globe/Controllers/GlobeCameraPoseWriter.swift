//
//  GlobeCameraPoseWriter.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import Foundation
import simd

/// Builds camera transforms that keep the globe upright while looking at origin.
///
/// This isolates SceneKit-agnostic matrix math from the controller state machine.
enum GlobeCameraPoseWriter {
    /// Returns a world transform for a camera positioned at `position`.
    static func makeTransform(lookingAtOriginFrom position: simd_float3) -> simd_float4x4 {
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

        return simd_float4x4(columns: (
            rotationMatrix.columns.0,
            rotationMatrix.columns.1,
            rotationMatrix.columns.2,
            simd_float4(position.x, position.y, position.z, 1)
        ))
    }
}
