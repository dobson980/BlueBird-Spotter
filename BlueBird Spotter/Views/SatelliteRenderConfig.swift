//
//  SatelliteRenderConfig.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/26/25.
//

import Foundation

/// Collects satellite rendering knobs so SwiftUI can tune SceneKit output live.
struct SatelliteRenderConfig: Equatable {
    /// Enables the USDZ model in production builds.
    var useModel: Bool
    /// Uniform scale for the satellite model in scene units.
    var scale: Float
    /// Base yaw offset applied after computed attitude (radians).
    var baseYaw: Float
    /// Base pitch offset applied after computed attitude (radians).
    var basePitch: Float
    /// Base roll offset applied after computed attitude (radians).
    var baseRoll: Float
    /// Aligns the model to face Earth (nadir) before applying offsets.
    var nadirPointing: Bool
    /// Spins the model around its radial axis to follow the velocity tangent.
    var yawFollowsOrbit: Bool

    /// Production-tuned defaults for release builds.
    static let productionDefaults = SatelliteRenderConfig(
        useModel: true,
        scale: 0.006,
        baseYaw: 0,
        basePitch: 0,
        baseRoll: 0,
        nadirPointing: true,
        yawFollowsOrbit: true
    )

    /// Debug defaults act as a safe baseline for live tuning.
    static let debugDefaults = SatelliteRenderConfig(
        useModel: true,
        scale: 0.01,
        baseYaw: 0,
        basePitch: 0,
        baseRoll: 0,
        nadirPointing: true,
        yawFollowsOrbit: true
    )
}
