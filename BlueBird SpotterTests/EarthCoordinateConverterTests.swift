//
//  EarthCoordinateConverterTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import SatKit
import Testing
@testable import BlueBird_Spotter

/// Exercises the coordinate conversion pipeline used by the SGP4 orbit engine.
struct EarthCoordinateConverterTests {

    /// Ensures geodetic conversion returns bounded, finite values for a known TLE.
    @Test @MainActor func temeToGeodetic_outputsValidRanges() throws {
        let elements = try SatKit.Elements(
            "00005",
            "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753",
            "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667"
        )
        let satellite = SatKit.Satellite(elements: elements)
        let epochDate = Date(ds1950: elements.t₀)

        let position = try satellite.position(minsAfterEpoch: 0.0)
        let geodetic = EarthCoordinateConverter.temeToGeodetic(
            position: SIMD3(position.x, position.y, position.z),
            at: epochDate
        )

        #expect(geodetic.latitudeDegrees.isFinite)
        #expect(geodetic.longitudeDegrees.isFinite)
        #expect(geodetic.altitudeKm.isFinite)
        #expect(geodetic.latitudeDegrees >= -90.0)
        #expect(geodetic.latitudeDegrees <= 90.0)
        #expect(geodetic.longitudeDegrees >= -180.0)
        #expect(geodetic.longitudeDegrees <= 180.0)
        #expect(geodetic.altitudeKm > -100.0)
    }

    /// Confirms the SGP4 engine surfaces sane geodetic coordinates at epoch.
    @Test @MainActor func sgp4OrbitEngine_outputsValidGeodeticRanges() throws {
        let engine = SGP4OrbitEngine()
        let satellite = Satellite(
            id: 5,
            name: "00005",
            tleLine1: "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753",
            tleLine2: "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667",
            epoch: nil
        )
        let elements = try SatKit.Elements(satellite.name, satellite.tleLine1, satellite.tleLine2)
        let epochDate = Date(ds1950: elements.t₀)

        let position = try engine.position(for: satellite, at: epochDate)

        #expect(position.latitudeDegrees >= -90.0)
        #expect(position.latitudeDegrees <= 90.0)
        #expect(position.longitudeDegrees >= -180.0)
        #expect(position.longitudeDegrees <= 180.0)
        #expect(position.altitudeKm.isFinite)
        #expect(position.altitudeKm > -100.0)
    }
}
