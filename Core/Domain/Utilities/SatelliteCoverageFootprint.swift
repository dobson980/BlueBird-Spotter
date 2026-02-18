//
//  SatelliteCoverageFootprint.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/17/26.
//

import Foundation

/// Geometry-only helpers for estimating a satellite's ground coverage footprint.
///
/// Why this exists:
/// - Globe rendering needs a consistent way to size educational coverage overlays.
/// - Keeping the math in `Core` makes it easy to test and reuse.
///
/// What this does NOT do:
/// - It does not model RF link budget, terrain blocking, weather, or policy limits.
/// - It intentionally provides a rough, educational estimate.
enum SatelliteCoverageFootprint {
    /// Default minimum elevation angle used by the app's educational overlay.
    nonisolated static let defaultMinimumElevationDegrees: Double = 20

    /// Computes the geocentric half-angle from nadir to the footprint edge.
    ///
    /// The result is the Earth-centered angle between:
    /// 1) the sub-satellite point, and
    /// 2) the estimated coverage boundary.
    ///
    /// Formula assumes a spherical Earth and a fixed minimum elevation threshold.
    nonisolated static func geocentricHalfAngleRadians(
        altitudeKm: Double,
        minimumElevationDegrees: Double = defaultMinimumElevationDegrees,
        earthRadiusKm: Double = GlobeCoordinateConverter.earthRadiusKm
    ) -> Double? {
        guard earthRadiusKm > 0 else { return nil }
        let orbitalRadiusKm = earthRadiusKm + altitudeKm
        // If a satellite is not above the Earth surface, the footprint is undefined.
        guard orbitalRadiusKm > earthRadiusKm else { return nil }

        let minimumElevationRadians = minimumElevationDegrees * .pi / 180
        let cosineArgument = (earthRadiusKm / orbitalRadiusKm) * cos(minimumElevationRadians)
        // Clamp for numerical stability near floating-point limits.
        let clampedCosine = min(max(cosineArgument, -1), 1)
        let halfAngle = acos(clampedCosine) - minimumElevationRadians

        guard halfAngle.isFinite, halfAngle > 0 else { return nil }
        return halfAngle
    }

    /// Returns the estimated ground radius (great-circle distance) in kilometers.
    nonisolated static func groundRadiusKm(
        altitudeKm: Double,
        minimumElevationDegrees: Double = defaultMinimumElevationDegrees,
        earthRadiusKm: Double = GlobeCoordinateConverter.earthRadiusKm
    ) -> Double? {
        guard let halfAngle = geocentricHalfAngleRadians(
            altitudeKm: altitudeKm,
            minimumElevationDegrees: minimumElevationDegrees,
            earthRadiusKm: earthRadiusKm
        ) else {
            return nil
        }

        return earthRadiusKm * halfAngle
    }

    /// Converts a ground-radius estimate into an Earth-centered half-angle.
    nonisolated static func geocentricHalfAngleRadians(
        groundRadiusKm: Double,
        earthRadiusKm: Double = GlobeCoordinateConverter.earthRadiusKm
    ) -> Double? {
        guard earthRadiusKm > 0, groundRadiusKm > 0 else { return nil }
        let halfAngle = groundRadiusKm / earthRadiusKm
        guard halfAngle.isFinite, halfAngle > 0 else { return nil }
        return min(halfAngle, Double.pi)
    }
}
