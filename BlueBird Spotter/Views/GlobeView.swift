//
//  GlobeView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import SwiftUI

/// Shows a 3D globe with tracked satellites and selection details.
struct GlobeView: View {
    /// Local tracking view model keeps the globe fed with positions.
    @State private var viewModel: TrackingViewModel
    /// Currently selected satellite for the detail overlay.
    @State private var selectedSatelliteId: Int?

    /// Allows previews to inject a prepared view model.
    init(viewModel: TrackingViewModel = TrackingViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GlobeSceneView(
                trackedSatellites: viewModel.trackedSatellites,
                onSelect: { selectedSatelliteId = $0 }
            )

            if let selected = selectedSatellite {
                GlobeSelectionOverlay(trackedSatellite: selected)
                    .padding()
            }
        }
        .task {
            guard !isPreview else { return }
            // Starts the tracking loop when the globe becomes active.
            viewModel.startTracking(queryKey: "SPACEMOBILE")
        }
        .onDisappear {
            // Cancels tracking to avoid background work when the tab is hidden.
            viewModel.stopTracking()
        }
    }

    /// Looks up the selected satellite for overlay display.
    private var selectedSatellite: TrackedSatellite? {
        guard let selectedSatelliteId else { return nil }
        return viewModel.trackedSatellites.first { $0.satellite.id == selectedSatelliteId }
    }

    /// Detects when the view is running in Xcode previews.
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

/// Overlay view that summarizes the tapped satellite.
private struct GlobeSelectionOverlay: View {
    let trackedSatellite: TrackedSatellite

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trackedSatellite.satellite.name)
                .font(.headline)
            Text("Lat: \(formatDegrees(trackedSatellite.position.latitudeDegrees))")
            Text("Lon: \(formatDegrees(trackedSatellite.position.longitudeDegrees))")
            Text("Alt: \(formatKilometers(trackedSatellite.position.altitudeKm)) km")
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
}

/// Preview for validating the globe overlay layout.
#Preview {
    GlobeView(viewModel: .previewModel())
}

private extension TrackingViewModel {
    /// Provides sample data for previewing the globe without network access.
    static func previewModel() -> TrackingViewModel {
        let viewModel = TrackingViewModel()
        let now = Date()
        let sampleSatellite = Satellite(
            id: 67890,
            name: "BLUEBIRD-GLOBE",
            tleLine1: "1 67890U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991",
            tleLine2: "2 67890  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456",
            epoch: now
        )
        let samplePosition = SatellitePosition(
            timestamp: now,
            latitudeDegrees: 12.34,
            longitudeDegrees: 56.78,
            altitudeKm: 550.2
        )
        let tracked = [TrackedSatellite(satellite: sampleSatellite, position: samplePosition)]
        viewModel.trackedSatellites = tracked
        viewModel.state = .loaded(tracked)
        viewModel.lastUpdatedAt = now
        return viewModel
    }
}
