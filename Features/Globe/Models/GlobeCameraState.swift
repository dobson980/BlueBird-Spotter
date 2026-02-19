//
//  GlobeCameraState.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/18/26.
//

import Foundation
import simd

/// Active camera gesture tracked by the globe camera state machine.
enum GlobeCameraActiveGesture: Equatable {
    case pan
    case pinch
}

/// Complete mutable state for the globe camera state machine.
///
/// Why this exists:
/// - Camera behavior must be predictable across repeated selection and gesture flows.
/// - Keeping state in one model allows unit tests to verify behavior without SceneKit UI.
///
/// What this does NOT do:
/// - It does not contain interpolation math implementation.
///   `GlobeCameraController` owns interpolation and node writes.
struct GlobeCameraState: Equatable {
    /// Current camera interaction mode.
    var mode: GlobeCameraMode
    /// Normalized direction from Earth origin to camera.
    var direction: simd_float3
    /// Camera distance from Earth origin.
    var distance: Float
    /// Satellite currently selected by UI intent, if any.
    var selectedSatelliteId: Int?
    /// Gesture currently mutating the camera pose, if any.
    var activeGesture: GlobeCameraActiveGesture?
    /// In-flight transition metadata, if a transition is active.
    var transition: GlobeCameraTransition?
    /// Last focus token consumed from cross-tab requests.
    var lastFocusToken: UUID?

    /// Current transition progress for diagnostics overlays.
    var transitionProgress: Float {
        transition?.transitionProgress ?? 0
    }

    /// Follow target projection for diagnostics overlays.
    var followSatelliteId: Int? {
        mode.followSatelliteId
    }
}
