//
//  SGP4OrbitEngine.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import SatKit

/// Orbit engine that uses SatelliteKit's SGP4 implementation under the app contract.
///
/// This keeps the app-level `Satellite` model stable while delegating propagation
/// to SatelliteKit and converting TEME-style coordinates into geodetic latitude,
/// longitude, and altitude for UI display.
struct SGP4OrbitEngine: OrbitEngine {
    /// Produces a geodetic position by propagating the satellite's TLE to a date.
    ///
    /// Nonisolated so the tracking loop can compute on a background task.
    nonisolated func position(for satellite: Satellite, at date: Date) throws -> SatellitePosition {
        let elements = try SatKit.Elements(satellite.name, satellite.tleLine1, satellite.tleLine2)
        // Use the legacy propagator so outputs align with Vallado reference vectors.
        let propagator = SatKit.selectPropagatorLegacy(elements)
        let minutesSinceEpoch = date.timeIntervalSince(Date(ds1950: elements.t₀)) / 60.0
        let pvCoordinates = try propagator.getPVCoordinates(minsAfterEpoch: minutesSinceEpoch)
        let eciPosition = SIMD3(
            pvCoordinates.position.x / 1000.0,
            pvCoordinates.position.y / 1000.0,
            pvCoordinates.position.z / 1000.0
        )
        let geodetic = EarthCoordinateConverter.temeToGeodetic(position: eciPosition, at: date)

        return SatellitePosition(
            timestamp: date,
            latitudeDegrees: geodetic.latitudeDegrees,
            longitudeDegrees: geodetic.longitudeDegrees,
            altitudeKm: geodetic.altitudeKm
        )
    }
}
