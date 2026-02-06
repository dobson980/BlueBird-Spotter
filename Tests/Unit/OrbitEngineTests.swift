//
//  OrbitEngineTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Validates deterministic behavior and bounds for the stub orbit engine.
struct OrbitEngineTests {

    /// Ensures repeated calls with the same input return identical output.
    @Test @MainActor func stubOrbitEngine_isDeterministic() throws {
        let engine = StubOrbitEngine()
        let satellite = Satellite(
            id: 54001,
            name: "BLUEBIRD-1",
            tleLine1: "1 54001U 23001A   25001.12345678  .00001234  00000-0  10270-3 0  9991",
            tleLine2: "2 54001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456",
            epoch: nil
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try engine.position(for: satellite, at: date)
        let second = try engine.position(for: satellite, at: date)

        #expect(first == second)
    }

    /// Confirms the stub output stays within expected geodetic ranges.
    @Test @MainActor func stubOrbitEngine_outputsWithinBounds() throws {
        let engine = StubOrbitEngine()
        let satellite = Satellite(
            id: 54002,
            name: "BLUEBIRD-2",
            tleLine1: "1 54002U 23002A   25001.12345678  .00001234  00000-0  10270-3 0  9992",
            tleLine2: "2 54002  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123457",
            epoch: nil
        )
        let date = Date(timeIntervalSince1970: 1_700_123_456)

        let position = try engine.position(for: satellite, at: date)

        #expect(position.latitudeDegrees >= -90.0)
        #expect(position.latitudeDegrees <= 90.0)
        #expect(position.longitudeDegrees >= -180.0)
        #expect(position.longitudeDegrees <= 180.0)
        #expect(position.altitudeKm >= 200.0)
        #expect(position.altitudeKm <= 2000.0)
    }
}
