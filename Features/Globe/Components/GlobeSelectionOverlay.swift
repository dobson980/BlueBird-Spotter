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
