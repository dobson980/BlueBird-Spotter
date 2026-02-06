//
//  SGP4GoldenTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import SatKit
import Testing
@testable import BlueBird_Spotter

/// Validates SatelliteKit propagation against Vallado's reference vectors.
struct SGP4GoldenTests {

    /// Confirms the Vallado case 00005 TEME position/velocity matches reference outputs.
    @Test @MainActor func sgp4GoldenCase00005_matchesReferenceOutput() throws {
        let elements = try SatKit.Elements(
            "00005",
            "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753",
            "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667"
        )
        // The legacy propagator matches Vallado's published verification vectors.
        let propagator = SatKit.selectPropagatorLegacy(elements)

        let expectedPositionAtZero = SatKit.Vector(7022.46529266, -1400.08296755, 0.03995155)
        let expectedVelocityAtZero = SatKit.Vector(1.893841015, 6.405893759, 4.534807250)
        let expectedPositionAt4320 = SatKit.Vector(-9060.47373569, 4658.70952502, 813.68673153)
        let expectedVelocityAt4320 = SatKit.Vector(-2.232832783, -4.110453490, -3.157345433)
        // Long-range propagation can diverge slightly across SGP4 implementations, so we assert
        // "near Vallado" while delegating math correctness to SatelliteKit.
        let positionToleranceKm = 0.1
        let velocityToleranceKmPerSec = 1e-4

        let pvAtZero = try propagator.getPVCoordinates(minsAfterEpoch: 0.0)
        let pvAt4320 = try propagator.getPVCoordinates(minsAfterEpoch: 4320.0)
        let positionAtZero = SatKit.Vector(
            pvAtZero.position.x / 1000.0,
            pvAtZero.position.y / 1000.0,
            pvAtZero.position.z / 1000.0
        )
        let velocityAtZero = SatKit.Vector(
            pvAtZero.velocity.x / 1000.0,
            pvAtZero.velocity.y / 1000.0,
            pvAtZero.velocity.z / 1000.0
        )
        let positionAt4320 = SatKit.Vector(
            pvAt4320.position.x / 1000.0,
            pvAt4320.position.y / 1000.0,
            pvAt4320.position.z / 1000.0
        )
        let velocityAt4320 = SatKit.Vector(
            pvAt4320.velocity.x / 1000.0,
            pvAt4320.velocity.y / 1000.0,
            pvAt4320.velocity.z / 1000.0
        )

        expectVector(positionAtZero, matches: expectedPositionAtZero, tolerance: positionToleranceKm)
        expectVector(velocityAtZero, matches: expectedVelocityAtZero, tolerance: velocityToleranceKmPerSec)
        expectVector(positionAt4320, matches: expectedPositionAt4320, tolerance: positionToleranceKm)
        expectVector(velocityAt4320, matches: expectedVelocityAt4320, tolerance: velocityToleranceKmPerSec)
    }

    @MainActor private func expectVector(_ actual: SatKit.Vector, matches expected: SatKit.Vector, tolerance: Double) {
        let xDelta = abs(actual.x - expected.x)
        let yDelta = abs(actual.y - expected.y)
        let zDelta = abs(actual.z - expected.z)

        #expect(xDelta <= tolerance, "x \(actual.x) vs \(expected.x) delta \(xDelta) exceeds \(tolerance)")
        #expect(yDelta <= tolerance, "y \(actual.y) vs \(expected.y) delta \(yDelta) exceeds \(tolerance)")
        #expect(zDelta <= tolerance, "z \(actual.z) vs \(expected.z) delta \(zDelta) exceeds \(tolerance)")
    }
}
