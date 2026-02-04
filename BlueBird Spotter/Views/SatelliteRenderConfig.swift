//
//  SatelliteRenderConfig.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/26/25.
//

import Foundation

/// Controls which satellite detail tier is used for scene rendering.
enum SatelliteDetailMode: Equatable {
    /// Forces every satellite to use the low-detail model.
    case lowOnly
    /// Uses the high-detail model for the selected satellite only.
    case lowWithHighForSelection
}

/// Collects satellite rendering knobs so SwiftUI can tune SceneKit output live.
struct SatelliteRenderConfig: Equatable {
    /// Enables the USDZ model in production builds.
    var useModel: Bool
    /// Uniform scale for the satellite model in scene units.
    ///
    /// Smaller values help reduce overlap when many satellites are visible at once.
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
    /// Additional heading offset applied around the radial axis (radians).
    ///
    /// This keeps the satellite's long face aligned with the orbit track
    /// without changing its relationship to Earth.
    var orbitHeadingOffset: Float
    /// Chooses whether the high-detail model is reserved for selection.
    var detailMode: SatelliteDetailMode
    /// Caps how many satellites can use the high-detail model at once.
    var maxDetailModels: Int
    /// Camera distance thresholds for switching to lower LOD geometries.
    var lodDistances: [Float]

    /// Production-tuned defaults for release builds.
    static let productionDefaults = SatelliteRenderConfig(
        useModel: true,
        // Reduced scale keeps nearby satellites from overlapping at default zoom.
        scale: 0.003,
        baseYaw: 0,
        basePitch: 0,
        // Rotate the model so its body reads level relative to Earth.
        baseRoll: .pi / 4,
        nadirPointing: true,
        // Align the model with its orbital heading for a consistent top-down view.
        yawFollowsOrbit: true,
        orbitHeadingOffset: .pi / 4,
        detailMode: .lowWithHighForSelection,
        maxDetailModels: 1,
        lodDistances: [2.0]
    )

    /// Debug defaults act as a safe baseline for live tuning.
    static let debugDefaults = SatelliteRenderConfig(
        useModel: true,
        scale: 0.003,
        baseYaw: 0,
        basePitch: 0,
        // Matches production to keep debug previews consistent.
        baseRoll: .pi / 4,
        nadirPointing: true,
        yawFollowsOrbit: true,
        orbitHeadingOffset: .pi / 4,
        detailMode: .lowWithHighForSelection,
        maxDetailModels: 1,
        lodDistances: [2.0]
    )
}
