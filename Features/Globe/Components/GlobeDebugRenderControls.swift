//
//  GlobeDebugRenderControls.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import SwiftUI

/// Debug-only control panel for tuning satellite render orientation and scale.
///
/// This is intentionally isolated so release-facing UI remains easy to read and
/// contributors can find debug tooling in a dedicated file.
struct GlobeDebugRenderControls: View {
    @Binding var satelliteScale: Double
    @Binding var satelliteBaseYawDegrees: Double
    @Binding var satelliteBasePitchDegrees: Double
    @Binding var satelliteBaseRollDegrees: Double
    @Binding var satelliteOrbitHeadingDegrees: Double
    @Binding var satelliteNadirPointing: Bool
    @Binding var satelliteYawFollowsOrbit: Bool

    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Satellite Tuning")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Scale: \(satelliteScale, specifier: "%.3f")")
                Slider(value: $satelliteScale, in: 0.001...0.05)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Yaw Offset: \(satelliteBaseYawDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteBaseYawDegrees, in: -180...180, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pitch Offset: \(satelliteBasePitchDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteBasePitchDegrees, in: -180...180, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Roll Offset: \(satelliteBaseRollDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteBaseRollDegrees, in: -180...180, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Orbit Heading: \(satelliteOrbitHeadingDegrees, specifier: "%.0f")°")
                Slider(value: $satelliteOrbitHeadingDegrees, in: -180...180, step: 1)
            }

            Toggle("Nadir Pointing", isOn: $satelliteNadirPointing)
            Toggle("Yaw Follows Orbit", isOn: $satelliteYawFollowsOrbit)

            Button("Reset") {
                onReset()
            }
        }
        .font(.caption)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Debug-only lightweight render diagnostics panel.
struct GlobeDebugStatsOverlay: View {
    let trackedCount: Int
    let renderStats: GlobeRenderStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Globe Stats")
                .font(.headline)
            Text("Tracked: \(trackedCount)")
            Text("Nodes: \(renderStats?.nodeCount ?? 0)")
            Text("Template Loaded: \(renderStats?.templateLoaded == true ? "Yes" : "No")")
            Text("Uses Models: \(renderStats?.usesModelTemplates == true ? "Yes" : "No")")
            Text("Simulator: \(renderStats?.isSimulator == true ? "Yes" : "No")")
        }
        .font(.caption2)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
