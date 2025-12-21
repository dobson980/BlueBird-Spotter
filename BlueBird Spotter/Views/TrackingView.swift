//
//  TrackingView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import SwiftUI

/// Presents the live tracking loop output for each satellite.
///
/// The layout emphasizes a quick glance at name, location, and update time.
struct TrackingView: View {
    /// Local view model state so the UI refreshes with tracking updates.
    @State private var viewModel: TrackingViewModel

    /// Allows previews to inject a prepared view model.
    init(viewModel: TrackingViewModel = TrackingViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header icon to distinguish the tracking tab.
            Image(systemName: "location.north.circle")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Group {
                switch viewModel.state {
                case .idle:
                    Text("Tracking is idle.")
                case .loading:
                    ProgressView("Starting tracking...")
                case .loaded(let trackedSatellites):
                    // Surface the latest update so refresh cadence is visible.
                    if let lastUpdatedAt = viewModel.lastUpdatedAt {
                        Text("Last update: \(lastUpdatedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    List(trackedSatellites) { tracked in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tracked.satellite.name)
                                .font(.headline)
                            Text("Lat: \(formatDegrees(tracked.position.latitudeDegrees))")
                                .font(.caption)
                                .monospaced()
                            Text("Lon: \(formatDegrees(tracked.position.longitudeDegrees))")
                                .font(.caption)
                                .monospaced()
                            Text("Alt: \(formatKilometers(tracked.position.altitudeKm)) km")
                                .font(.caption)
                                .monospaced()
                        }
                    }
                case .error(let message):
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .task {
            guard !isPreview else { return }
            // Begin tracking when the view becomes active.
            viewModel.startTracking(queryKey: "SPACEMOBILE")
        }
        .onDisappear {
            // Stop background work when the tab is no longer visible.
            viewModel.stopTracking()
        }
        .padding()
    }

    /// Rounds degrees for a compact UI-friendly readout.
    private func formatDegrees(_ value: Double) -> String {
        String(format: "%.2f°", value)
    }

    /// Rounds kilometers for a compact UI-friendly readout.
    private func formatKilometers(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Detects when the view is running in Xcode previews.
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

/// Preview for validating tracking layout without live data.
#Preview {
    TrackingView(viewModel: .previewModel())
}

private extension TrackingViewModel {
    /// Provides sample data for previewing tracking without network access.
    static func previewModel() -> TrackingViewModel {
        let viewModel = TrackingViewModel()
        let now = Date()
        let sampleSatellite = Satellite(
            id: 12345,
            name: "BLUEBIRD-TRACK",
            tleLine1: "1 12345U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991",
            tleLine2: "2 12345  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456",
            epoch: now
        )
        let samplePosition = SatellitePosition(
            timestamp: now,
            latitudeDegrees: 37.77,
            longitudeDegrees: -122.42,
            altitudeKm: 550.2
        )
        let tracked = [TrackedSatellite(satellite: sampleSatellite, position: samplePosition)]
        viewModel.trackedSatellites = tracked
        viewModel.state = .loaded(tracked)
        viewModel.lastUpdatedAt = now
        return viewModel
    }
}
