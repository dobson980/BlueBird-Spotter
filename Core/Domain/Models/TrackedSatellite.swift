//
//  TrackedSatellite.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation

/// Combines a satellite with its most recent computed position.
struct TrackedSatellite: Sendable, Equatable, Identifiable {
    /// Stable identity derived from the underlying satellite.
    var id: Int { satellite.id }

    let satellite: Satellite
    let position: SatellitePosition
}
