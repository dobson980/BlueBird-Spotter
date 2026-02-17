//
//  SatelliteCoverageFootprintTests.swift
//  BlueBird SpotterTests
//
//  Created by Codex on 2/17/26.
//

import Testing
@testable import BlueBird_Spotter

/// Validates geometry-only coverage footprint estimates.
struct SatelliteCoverageFootprintTests {
    /// Confirms the 520 km / 20° estimate matches the expected high-level radius.
    @Test func groundRadius_520km_20deg_matchesReferenceEstimate() {
        let radius = SatelliteCoverageFootprint.groundRadiusKm(
            altitudeKm: 520,
            minimumElevationDegrees: 20
        )

        #expect(radius != nil)
        #expect(abs((radius ?? 0) - 1_076.6) < 2.0)
    }

    /// Confirms the 690 km / 20° estimate tracks the expected larger footprint.
    @Test func groundRadius_690km_20deg_matchesReferenceEstimate() {
        let radius = SatelliteCoverageFootprint.groundRadiusKm(
            altitudeKm: 690,
            minimumElevationDegrees: 20
        )

        #expect(radius != nil)
        #expect(abs((radius ?? 0) - 1_336.5) < 2.0)
    }

    /// Lower elevation masks should produce broader footprint estimates.
    @Test func groundRadius_lowerElevation_increasesCoverage() {
        let conservative = SatelliteCoverageFootprint.groundRadiusKm(
            altitudeKm: 520,
            minimumElevationDegrees: 20
        ) ?? 0
        let permissive = SatelliteCoverageFootprint.groundRadiusKm(
            altitudeKm: 520,
            minimumElevationDegrees: 10
        ) ?? 0

        #expect(permissive > conservative)
    }

    /// Coverage is undefined when altitude is at or below Earth radius baseline.
    @Test func groundRadius_nonPositiveOrbitalAltitude_returnsNil() {
        let radius = SatelliteCoverageFootprint.groundRadiusKm(
            altitudeKm: 0,
            minimumElevationDegrees: 20
        )

        #expect(radius == nil)
    }

    /// Fixed-radius estimates should map to a stable geocentric half-angle.
    @Test func geocentricHalfAngle_fromGroundRadius_matchesExpectedValue() {
        let halfAngle = SatelliteCoverageFootprint.geocentricHalfAngleRadians(groundRadiusKm: 500)

        #expect(halfAngle != nil)
        #expect(abs((halfAngle ?? 0) - 0.0785) < 0.001)
    }
}
