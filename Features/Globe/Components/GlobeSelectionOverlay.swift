//
//  GlobeSelectionOverlay.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import SwiftUI

/// Overlay view that summarizes the currently selected satellite.
///
/// Keeping this component separate from `GlobeView` keeps the root screen focused
/// on orchestration while this file owns compact value formatting.
struct GlobeSelectionOverlay: View {
    let trackedSatellite: TrackedSatellite

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trackedSatellite.satellite.name)
                .font(.headline)
            Text("Lat: \(formatDegrees(trackedSatellite.position.latitudeDegrees))")
            Text("Lon: \(formatDegrees(trackedSatellite.position.longitudeDegrees))")
            Text("Alt: \(formatKilometers(trackedSatellite.position.altitudeKm)) km")
            Text("Vel: \(formatVelocity(trackedSatellite.position.velocityKmPerSec))")
        }
        .font(.caption)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Rounds degrees for a compact overlay readout.
    private func formatDegrees(_ value: Double) -> String {
        String(format: "%.2f°", value)
    }

    /// Rounds kilometers for a compact overlay readout.
    private func formatKilometers(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Formats the satellite speed (magnitude of the velocity vector) in km/h.
    private func formatVelocity(_ velocityKmPerSec: SIMD3<Double>?) -> String {
        guard let velocityKmPerSec else { return "—" }
        let speedKmPerSec = (velocityKmPerSec.x * velocityKmPerSec.x
                             + velocityKmPerSec.y * velocityKmPerSec.y
                             + velocityKmPerSec.z * velocityKmPerSec.z).squareRoot()
        // Convert km/s to km/h for display so values are intuitive for non-experts.
        let speedKmPerHour = speedKmPerSec * 3600
        return String(format: "%.0f km/h", speedKmPerHour)
    }
}

/// Preview for validating the selection overlay with full telemetry values.
#Preview("With Velocity") {
    GlobeSelectionOverlay(trackedSatellite: GlobeSelectionOverlayPreviewFactory.withVelocity)
        .padding()
}

/// Preview for validating the velocity placeholder when speed is unavailable.
#Preview("No Velocity") {
    GlobeSelectionOverlay(trackedSatellite: GlobeSelectionOverlayPreviewFactory.withoutVelocity)
        .padding()
}

/// Preview fixtures for `GlobeSelectionOverlay`.
private enum GlobeSelectionOverlayPreviewFactory {
    /// Sample satellite containing a velocity vector.
    static let withVelocity = TrackedSatellite(
        satellite: Satellite(
            id: 45854,
            name: "BLUEBIRD-1",
            tleLine1: "1 45854U 20008A   26036.22192385  .00005457  00000+0  43089-3 0  9994",
            tleLine2: "2 45854  53.0544 292.8396 0001647  89.3122 270.8203 15.06378191327752",
            epoch: Date()
        ),
        position: SatellitePosition(
            timestamp: Date(),
            latitudeDegrees: 35.72,
            longitudeDegrees: -95.44,
            altitudeKm: 547.9,
            velocityKmPerSec: SIMD3(6.8, 2.0, -0.1)
        )
    )

    /// Sample satellite with missing velocity to exercise placeholder UI.
    static let withoutVelocity = TrackedSatellite(
        satellite: Satellite(
            id: 45955,
            name: "BLUEBIRD-2",
            tleLine1: "1 45955U 20040A   26036.13484363  .00004642  00000+0  37482-3 0  9998",
            tleLine2: "2 45955  53.0539 293.2265 0001579  90.5216 269.6102 15.06348287306616",
            epoch: Date()
        ),
        position: SatellitePosition(
            timestamp: Date(),
            latitudeDegrees: 14.12,
            longitudeDegrees: -28.65,
            altitudeKm: 546.3,
            velocityKmPerSec: nil
        )
    )
}
