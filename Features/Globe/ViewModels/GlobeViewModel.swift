//
//  GlobeViewModel.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import Foundation
import Observation

/// ViewModel for the globe screen.
///
/// This type keeps globe-specific UI state (selection, panel visibility, debug
/// stats) separate from rendering views, while delegating live position updates
/// to the tracking feature's `TrackingViewModel`.
@MainActor
@Observable
final class GlobeViewModel {
    /// Reused tracking view model that produces live satellite positions.
    let trackingViewModel: TrackingViewModel

    /// Currently selected satellite for detail overlays and high-detail rendering.
    var selectedSatelliteId: Int?

    /// Controls whether the top-right settings panel is expanded.
    var isSettingsExpanded = false

    #if DEBUG
    /// Latest render diagnostics emitted by `GlobeSceneView`.
    var renderStats: GlobeRenderStats?
    #endif

    init(trackingViewModel: TrackingViewModel = TrackingViewModel()) {
        self.trackingViewModel = trackingViewModel
    }

    /// Convenience projection of tracked satellites for view binding.
    var trackedSatellites: [TrackedSatellite] {
        trackingViewModel.trackedSatellites
    }

    /// Returns the selected satellite, if one is currently tracked.
    var selectedSatellite: TrackedSatellite? {
        guard let selectedSatelliteId else { return nil }
        return trackingViewModel.trackedSatellites.first { $0.satellite.id == selectedSatelliteId }
    }

    /// Starts the underlying tracking loop.
    func startTracking(queryKey: String) {
        trackingViewModel.startTracking(queryKey: queryKey)
    }

    /// Starts the underlying tracking loop using multiple query groups.
    func startTracking(queryKeys: [String]) {
        trackingViewModel.startTracking(queryKeys: queryKeys)
    }

    /// Stops the underlying tracking loop.
    func stopTracking() {
        trackingViewModel.stopTracking()
    }

    /// Mirrors a cross-tab focus request into local globe selection state.
    func syncSelection(with request: SatelliteFocusRequest?) {
        guard let request else { return }
        selectedSatelliteId = request.satelliteId
    }
}
