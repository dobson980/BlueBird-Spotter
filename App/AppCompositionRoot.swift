//
//  AppCompositionRoot.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/6/26.
//

import Foundation

/// Centralized dependency wiring for app-wide services and feature view models.
///
/// This is the composition root: one place that decides which concrete service
/// implementations each feature receives in production.
struct AppCompositionRoot {
    /// Shared TLE repository used across features.
    let repository: TLERepository
    /// Orbit engine implementation used by live tracking.
    let orbitEngine: any OrbitEngine

    /// Production dependency graph used by the running app.
    @MainActor
    static var live: AppCompositionRoot {
        AppCompositionRoot(
            repository: TLERepository.shared,
            orbitEngine: SGP4OrbitEngine()
        )
    }

    /// Builds the view model for the TLE list feature.
    func makeTLEViewModel() -> CelesTrakViewModel {
        CelesTrakViewModel(repository: repository)
    }

    /// Builds a tracking view model instance for screens that show live positions.
    func makeTrackingViewModel() -> TrackingViewModel {
        TrackingViewModel(
            repository: repository,
            orbitEngine: orbitEngine,
            ticker: RealTimeTicker()
        )
    }
}
