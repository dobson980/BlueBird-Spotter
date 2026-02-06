//
//  OrbitEngine.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation

/// Computes satellite positions from a TLE-based model.
///
/// Keeping this as a protocol makes it easy to swap in a real SGP4 engine later.
protocol OrbitEngine: Sendable {
    /// Returns a deterministic position for the given satellite and time.
    ///
    /// Marked nonisolated so tracking can compute off the main actor.
    nonisolated func position(for satellite: Satellite, at date: Date) throws -> SatellitePosition
}
