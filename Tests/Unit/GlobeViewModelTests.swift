//
//  GlobeViewModelTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 2/6/26.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Unit tests for globe-specific ViewModel decisions.
///
/// These tests stay UI-free so contributors can verify selection behavior
/// without launching SwiftUI views or SceneKit rendering.
struct GlobeViewModelTests {
    /// Builds a deterministic tracked satellite for selection tests.
    private func makeTrackedSatellite(id: Int, name: String) -> TrackedSatellite {
        TrackedSatellite(
            satellite: Satellite(
                id: id,
                name: name,
                tleLine1: "1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991",
                tleLine2: "2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456",
                epoch: nil
            ),
            position: SatellitePosition(
                timestamp: Date(timeIntervalSince1970: 1_000),
                latitudeDegrees: 10,
                longitudeDegrees: 20,
                altitudeKm: 540,
                velocityKmPerSec: nil
            )
        )
    }

    /// Confirms that a focus request updates globe selection state.
    @Test @MainActor func syncSelection_updatesSelectedSatelliteId() {
        let trackingViewModel = TrackingViewModel()
        let viewModel = GlobeViewModel(trackingViewModel: trackingViewModel)

        let request = SatelliteFocusRequest(satelliteId: 12345, token: UUID())
        viewModel.syncSelection(with: request)

        #expect(viewModel.selectedSatelliteId == 12345)
    }

    /// Confirms selection lookup resolves the matching tracked satellite model.
    @Test @MainActor func selectedSatellite_returnsMatchingTrackedSatellite() {
        let trackingViewModel = TrackingViewModel()
        trackingViewModel.trackedSatellites = [
            makeTrackedSatellite(id: 100, name: "ALPHA"),
            makeTrackedSatellite(id: 200, name: "BETA")
        ]

        let viewModel = GlobeViewModel(trackingViewModel: trackingViewModel)
        viewModel.selectedSatelliteId = 200

        #expect(viewModel.selectedSatellite?.satellite.name == "BETA")
        #expect(viewModel.selectedSatellite?.satellite.id == 200)
    }

    /// Confirms the derived selection returns nil when id is missing from tracking data.
    @Test @MainActor func selectedSatellite_returnsNilForMissingSelection() {
        let trackingViewModel = TrackingViewModel()
        trackingViewModel.trackedSatellites = [makeTrackedSatellite(id: 300, name: "GAMMA")]

        let viewModel = GlobeViewModel(trackingViewModel: trackingViewModel)
        viewModel.selectedSatelliteId = 999

        #expect(viewModel.selectedSatellite == nil)
    }
}
