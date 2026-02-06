//
//  SatellitePosition.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation

/// Describes a satellite's position in geodetic coordinates at a moment in time.
struct SatellitePosition: Sendable, Equatable {
    let timestamp: Date
    let latitudeDegrees: Double
    let longitudeDegrees: Double
    let altitudeKm: Double
    /// Velocity vector in km/s (TEME frame). Used for orbit-following orientation.
    let velocityKmPerSec: SIMD3<Double>?
}
