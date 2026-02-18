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

    /// Off-nadir scan limits should resolve to a valid positive half-angle at LEO altitudes.
    @Test func geocentricHalfAngle_offNadirLimit_520km_isFinite() {
        let halfAngle = SatelliteCoverageFootprint.geocentricHalfAngleRadians(
            altitudeKm: 520,
            maximumOffNadirDegrees: 58
        )

        #expect(halfAngle != nil)
        #expect((halfAngle ?? 0) > 0)
        #expect(abs((halfAngle ?? 0) - 0.1489) < 0.001)
    }

    /// A 20° profile at ~520 km should be clamped by the 58° off-nadir limit.
    @Test func geocentricHalfAngle_elevationAndScan_20deg_520km_appliesClamp() {
        let combined = SatelliteCoverageFootprint.geocentricHalfAngleRadians(
            altitudeKm: 520,
            minimumElevationDegrees: 20,
            maximumOffNadirDegrees: 58
        )
        let elevationOnly = SatelliteCoverageFootprint.geocentricHalfAngleRadians(
            altitudeKm: 520,
            minimumElevationDegrees: 20
        )
        let scanOnly = SatelliteCoverageFootprint.geocentricHalfAngleRadians(
            altitudeKm: 520,
            maximumOffNadirDegrees: 58
        )

        #expect(combined != nil)
        #expect(elevationOnly != nil)
        #expect(scanOnly != nil)
        #expect((combined ?? 0) < (elevationOnly ?? 0))
        #expect(abs((combined ?? 0) - (scanOnly ?? 0)) < 0.000001)
    }

    /// A 25° profile at ~520 km should remain elevation-limited (not scan-limited).
    @Test func geocentricHalfAngle_elevationAndScan_25deg_520km_staysElevationLimited() {
        let combined = SatelliteCoverageFootprint.geocentricHalfAngleRadians(
            altitudeKm: 520,
            minimumElevationDegrees: 25,
            maximumOffNadirDegrees: 58
        )
        let elevationOnly = SatelliteCoverageFootprint.geocentricHalfAngleRadians(
            altitudeKm: 520,
            minimumElevationDegrees: 25
        )

        #expect(combined != nil)
        #expect(elevationOnly != nil)
        #expect(abs((combined ?? 0) - (elevationOnly ?? 0)) < 0.000001)
    }

    /// With the same calibrated profile, higher altitude should still increase the coverage radius.
    @Test func groundRadius_elevationAndScan_higherAltitude_increasesCoverage() {
        let lowerAltitude = SatelliteCoverageFootprint.groundRadiusKm(
            altitudeKm: 520,
            minimumElevationDegrees: 20,
            maximumOffNadirDegrees: 58
        ) ?? 0
        let higherAltitude = SatelliteCoverageFootprint.groundRadiusKm(
            altitudeKm: 690,
            minimumElevationDegrees: 20,
            maximumOffNadirDegrees: 58
        ) ?? 0

        #expect(higherAltitude > lowerAltitude)
    }
}
