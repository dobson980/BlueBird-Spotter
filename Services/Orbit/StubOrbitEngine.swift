//
//  StubOrbitEngine.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation

/// Deterministic stub that produces stable-but-fake orbital positions.
///
/// The output stays within valid bounds so UI layers can rely on predictable data
/// until a real SGP4 implementation is introduced.
struct StubOrbitEngine: OrbitEngine {

    /// Computes a repeatable position derived from the satellite id and timestamp.
    ///
    /// Nonisolated so deterministic updates can run off the main actor.
    nonisolated func position(for satellite: Satellite, at date: Date) throws -> SatellitePosition {
        var generator = DeterministicGenerator(seed: makeSeed(id: satellite.id, date: date))

        let latitude = generator.nextUnit() * 180.0 - 90.0
        let longitude = generator.nextUnit() * 360.0 - 180.0
        let altitude = 200.0 + generator.nextUnit() * 1800.0

        return SatellitePosition(
            timestamp: date,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            altitudeKm: altitude,
            velocityKmPerSec: nil
        )
    }

    /// Combines the satellite id and timestamp into a stable 64-bit seed.
    nonisolated private func makeSeed(id: Int, date: Date) -> UInt64 {
        let time = Int64(date.timeIntervalSince1970.rounded(.down))
        var seed = UInt64(bitPattern: Int64(id)) ^ UInt64(bitPattern: time)
        seed &+= 0x9E3779B97F4A7C15
        seed ^= seed >> 30
        seed &*= 0xBF58476D1CE4E5B9
        seed ^= seed >> 27
        seed &*= 0x94D049BB133111EB
        seed ^= seed >> 31
        return seed
    }

    /// Lightweight deterministic generator for repeatable, unit-range values.
    private struct DeterministicGenerator {
        private var state: UInt64

        nonisolated init(seed: UInt64) {
            state = seed
        }

        nonisolated mutating func nextUnit() -> Double {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            let value = Double(state >> 11) / Double(1 << 53)
            return min(max(value, 0.0), 1.0)
        }
    }
}
