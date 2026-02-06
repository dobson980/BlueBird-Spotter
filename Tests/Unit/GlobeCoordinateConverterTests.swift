//
//  GlobeCoordinateConverterTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/21/25.
//

import Foundation
import SceneKit
import Testing
import simd
@testable import BlueBird_Spotter

/// Verifies the math that maps geodetic coordinates onto the SceneKit globe.
struct GlobeCoordinateConverterTests {
    /// Equator + prime meridian should land on the positive Z axis.
    @Test func equatorPrimeMeridian_mapsToPositiveZ() {
        let position = GlobeCoordinateConverter.scenePosition(
            from: SatellitePosition(timestamp: Date(), latitudeDegrees: 0, longitudeDegrees: 0, altitudeKm: 0, velocityKmPerSec: nil),
            earthRadiusScene: 1.0
        )
        #expect(abs(position.x) < 1e-6)
        #expect(abs(position.y) < 1e-6)
        #expect(abs(position.z - 1.0) < 1e-6)
    }

    /// Equator + 90E longitude should land on the positive X axis.
    @Test func equatorEastLongitude_mapsToPositiveX() {
        let position = GlobeCoordinateConverter.scenePosition(
            from: SatellitePosition(timestamp: Date(), latitudeDegrees: 0, longitudeDegrees: 90, altitudeKm: 0, velocityKmPerSec: nil),
            earthRadiusScene: 1.0
        )
        #expect(abs(position.x - 1.0) < 1e-6)
        #expect(abs(position.y) < 1e-6)
        #expect(abs(position.z) < 1e-6)
    }

    /// North pole should land on the positive Y axis.
    @Test func northPole_mapsToYAxis() {
        let position = GlobeCoordinateConverter.scenePosition(
            from: SatellitePosition(timestamp: Date(), latitudeDegrees: 90, longitudeDegrees: 0, altitudeKm: 0, velocityKmPerSec: nil),
            earthRadiusScene: 1.0
        )
        #expect(abs(position.x) < 1e-6)
        #expect(abs(position.y - 1.0) < 1e-6)
        #expect(abs(position.z) < 1e-6)
    }

    /// Verifies the pure-SIMD overload follows the same axis convention.
    @Test func simdOverload_equatorPrimeMeridian_mapsToPositiveZ() {
        let position = GlobeCoordinateConverter.scenePosition(
            latitudeDegrees: 0,
            longitudeDegrees: 0,
            altitudeKm: 0
        )
        #expect(abs(position.x) < 1e-6)
        #expect(abs(position.y) < 1e-6)
        #expect(abs(position.z - 1.0) < 1e-6)
    }

    /// Verifies zero velocity falls back to a safe default direction.
    @Test func sceneVelocityDirection_zeroVector_returnsDefaultForward() {
        let direction = GlobeCoordinateConverter.sceneVelocityDirection(
            from: SIMD3<Double>(0, 0, 0),
            at: Date(timeIntervalSince1970: 1_000)
        )
        #expect(direction.x == 0)
        #expect(direction.y == 0)
        #expect(direction.z == 1)
    }

    /// Verifies non-zero velocity is normalized for stable orientation math.
    @Test func sceneVelocityDirection_nonZero_isNormalized() {
        let direction = GlobeCoordinateConverter.sceneVelocityDirection(
            from: SIMD3<Double>(7.5, 1.2, 0.4),
            at: Date(timeIntervalSince1970: 1_000)
        )
        let length = simd_length(direction)
        #expect(direction.x.isFinite)
        #expect(direction.y.isFinite)
        #expect(direction.z.isFinite)
        #expect(abs(length - 1) < 0.0001)
    }
}
