//
//  GlobeDebugRenderControls.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/6/26.
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
            Text("Camera Mode: \(cameraModeLabel(renderStats?.cameraMode))")
            Text("Camera Distance: \(renderStats?.cameraDistance ?? 0, specifier: "%.2f")")
            Text("Following: \(renderStats?.followSatelliteId.map(String.init) ?? "None")")
            Text("Simulator: \(renderStats?.isSimulator == true ? "Yes" : "No")")
        }
        .font(.caption2)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Converts camera mode into a compact debug string.
    private func cameraModeLabel(_ mode: GlobeCameraMode?) -> String {
        guard let mode else { return "None" }
        switch mode {
        case .freeOrbit:
            return "Free Orbit"
        case .transitioning(let satelliteId):
            return "Transitioning(\(satelliteId))"
        case .following(let satelliteId):
            return "Following(\(satelliteId))"
        case .resettingHome:
            return "Resetting Home"
        }
    }
}

/// Preview container that provides mutable state bindings for debug controls.
private struct GlobeDebugRenderControlsPreviewHost: View {
    @State private var satelliteScale: Double = 0.003
    @State private var satelliteBaseYawDegrees: Double = 0
    @State private var satelliteBasePitchDegrees: Double = 0
    @State private var satelliteBaseRollDegrees: Double = 45
    @State private var satelliteOrbitHeadingDegrees: Double = 45
    @State private var satelliteNadirPointing = true
    @State private var satelliteYawFollowsOrbit = true

    var body: some View {
        GlobeDebugRenderControls(
            satelliteScale: $satelliteScale,
            satelliteBaseYawDegrees: $satelliteBaseYawDegrees,
            satelliteBasePitchDegrees: $satelliteBasePitchDegrees,
            satelliteBaseRollDegrees: $satelliteBaseRollDegrees,
            satelliteOrbitHeadingDegrees: $satelliteOrbitHeadingDegrees,
            satelliteNadirPointing: $satelliteNadirPointing,
            satelliteYawFollowsOrbit: $satelliteYawFollowsOrbit,
            onReset: {
                // Reset mirrors the same baseline used by the live debug panel.
                satelliteScale = 0.003
                satelliteBaseYawDegrees = 0
                satelliteBasePitchDegrees = 0
                satelliteBaseRollDegrees = 45
                satelliteOrbitHeadingDegrees = 45
                satelliteNadirPointing = true
                satelliteYawFollowsOrbit = true
            }
        )
        .frame(width: 320, alignment: .leading)
        .padding()
        // A solid backdrop makes thin-material controls readable in the preview canvas.
        .background(Color.black)
    }
}

/// Preview for tuning slider and toggle layout in the debug controls panel.
#Preview("Render Controls", traits: .sizeThatFitsLayout) {
    GlobeDebugRenderControlsPreviewHost()
}

/// Preview for validating populated render diagnostics.
#Preview("Stats Populated", traits: .sizeThatFitsLayout) {
    GlobeDebugStatsOverlay(
        trackedCount: 2,
        renderStats: GlobeRenderStats(
            trackedCount: 2,
            nodeCount: 5,
            usesModelTemplates: true,
            templateLoaded: true,
            cameraMode: .following(satelliteId: 45854),
            cameraDistance: 2.1,
            followSatelliteId: 45854,
            isPreview: true,
            isSimulator: true
        )
    )
    .frame(width: 220, alignment: .leading)
    .padding()
    .background(Color.black)
}

/// Preview for validating empty diagnostics fallback values.
#Preview("Stats Empty", traits: .sizeThatFitsLayout) {
    GlobeDebugStatsOverlay(
        trackedCount: 0,
        renderStats: nil
    )
    .frame(width: 220, alignment: .leading)
    .padding()
    .background(Color.black)
}
