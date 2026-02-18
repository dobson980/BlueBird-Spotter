//
//  GlobeCameraMode.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
//

/// High-level camera modes used by the globe camera state machine.
///
/// Why this exists:
/// - We need deterministic rules for focus, follow, and reset transitions.
/// - Gesture code should not infer intent from ad-hoc boolean flags.
///
/// What this does NOT do:
/// - It does not store camera vectors or timing details.
///   Those live in `GlobeCameraState` and `GlobeCameraTransition`.
enum GlobeCameraMode: Equatable {
    /// User-driven orbit navigation with no active follow target.
    case freeOrbit
    /// Camera is transitioning toward a selected satellite.
    case transitioning(toSatelliteId: Int)
    /// Camera is continuously following a selected satellite.
    case following(satelliteId: Int)
    /// Camera is animating back to the default home pose.
    case resettingHome

    /// Convenience projection for follow-target diagnostics.
    var followSatelliteId: Int? {
        switch self {
        case .transitioning(let satelliteId), .following(let satelliteId):
            return satelliteId
        case .freeOrbit, .resettingHome:
            return nil
        }
    }
}
