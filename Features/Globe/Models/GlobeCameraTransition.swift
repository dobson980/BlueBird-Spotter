//
//  GlobeCameraTransition.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
//

import simd

/// One deterministic camera transition in progress.
///
/// Why this exists:
/// - Selection and home reset both need time-based interpolation.
/// - We keep timing and pose anchors in one place so transition math is testable.
///
/// What this does NOT do:
/// - It does not mutate SceneKit nodes directly.
///   `GlobeCameraController` applies these values to the camera node.
struct GlobeCameraTransition: Equatable {
    /// Transition intent so completion behavior stays explicit.
    enum Kind: Equatable {
        case focus(satelliteId: Int)
        case resetHome
    }

    /// The transition intent being executed.
    let kind: Kind
    /// Camera direction when the transition began.
    let startDirection: simd_float3
    /// Camera distance when the transition began.
    let startDistance: Float
    /// Target direction anchor captured when the transition begins.
    ///
    /// Focus transitions may refresh this from live satellite positions, but this
    /// anchor provides a stable fallback if the target is temporarily unavailable.
    let targetDirection: simd_float3
    /// Target distance at the end of the transition.
    let targetDistance: Float
    /// Total transition duration in seconds.
    let duration: Float
    /// Fraction of the timeline reserved for orbit rotation before zoom.
    let rotationPhase: Float
    /// Elapsed transition time in seconds.
    var elapsed: Float

    /// Current normalized progress in [0, 1].
    var transitionProgress: Float {
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed / duration))
    }

    /// Follow target id when this transition is satellite-focused.
    var satelliteId: Int? {
        switch kind {
        case .focus(let satelliteId):
            return satelliteId
        case .resetHome:
            return nil
        }
    }
}
