//
//  TrackingViewModel+Preview.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/6/26.
//

import Foundation

/// Preview helpers for `TrackingViewModel` so SwiftUI previews stay self-contained.
extension TrackingViewModel {
    /// Shared preview satellite list so multiple preview states stay consistent.
    static var previewTrackedSatellites: [TrackedSatellite] {
        let now = Date()
        let sampleSatellite = Satellite(
            id: 12345,
            name: "BLUEBIRD-PREVIEW",
            tleLine1: "1 12345U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991",
            tleLine2: "2 12345  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456",
            epoch: now
        )
        let samplePosition = SatellitePosition(
            timestamp: now,
            latitudeDegrees: 37.77,
            longitudeDegrees: -122.42,
            altitudeKm: 550.2,
            velocityKmPerSec: nil
        )
        return [TrackedSatellite(satellite: sampleSatellite, position: samplePosition)]
    }

    /// Provides sample tracking data without any network access.
    ///
    /// This keeps previews fast and deterministic while demonstrating the same UI
    /// shape as live tracking updates.
    static func previewLoadedModel() -> TrackingViewModel {
        let viewModel = TrackingViewModel()
        let tracked = previewTrackedSatellites
        viewModel.trackedSatellites = tracked
        viewModel.state = .loaded(tracked)
        viewModel.lastUpdatedAt = tracked.first?.position.timestamp
        viewModel.lastTLEFetchedAt = tracked.first?.position.timestamp
        return viewModel
    }

    /// Provides a loading state preview for quick UI tuning.
    static func previewLoadingModel() -> TrackingViewModel {
        let viewModel = TrackingViewModel()
        viewModel.state = .loading
        return viewModel
    }

    /// Provides an error state preview for validating message and icon behavior.
    static func previewErrorModel() -> TrackingViewModel {
        let viewModel = TrackingViewModel()
        viewModel.state = .error("Tracking could not start because TLE data is temporarily unavailable.")
        return viewModel
    }

    /// Backwards-compatible alias used by existing preview call sites.
    static func previewModel() -> TrackingViewModel {
        let viewModel = previewLoadedModel()
        return viewModel
    }
}
