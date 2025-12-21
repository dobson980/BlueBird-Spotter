//
//  GlobeCoordinateConverterTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/21/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Verifies the math that maps geodetic coordinates onto the SceneKit globe.
struct GlobeCoordinateConverterTests {
    /// Equator + prime meridian should land on the positive X axis.
    @Test func equatorPrimeMeridian_mapsToXAxis() {
        let position = GlobeCoordinateConverter.scenePosition(
            latitudeDegrees: 0,
            longitudeDegrees: 0,
            altitudeKm: 0
        )
        #expect(abs(position.x - 1.0) < 1e-6)
        #expect(abs(position.y) < 1e-6)
        #expect(abs(position.z) < 1e-6)
    }

    /// Equator + 90E longitude should land on the positive Z axis.
    @Test func equatorEastLongitude_mapsToZAxis() {
        let position = GlobeCoordinateConverter.scenePosition(
            latitudeDegrees: 0,
            longitudeDegrees: 90,
            altitudeKm: 0
        )
        #expect(abs(position.x) < 1e-6)
        #expect(abs(position.y) < 1e-6)
        #expect(abs(position.z - 1.0) < 1e-6)
    }

    /// North pole should land on the positive Y axis.
    @Test func northPole_mapsToYAxis() {
        let position = GlobeCoordinateConverter.scenePosition(
            latitudeDegrees: 90,
            longitudeDegrees: 0,
            altitudeKm: 0
        )
        #expect(abs(position.x) < 1e-6)
        #expect(abs(position.y - 1.0) < 1e-6)
        #expect(abs(position.z) < 1e-6)
    }
}
