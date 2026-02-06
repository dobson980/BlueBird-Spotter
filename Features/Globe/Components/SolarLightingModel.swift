//
//  SolarLightingModel.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import Foundation
import simd

/// Computes the Sun's apparent direction so Earth lighting follows real UTC time.
///
/// This helper is intentionally pure math so the rendering layer can ask for
/// sunlight direction without owning astronomy equations directly.
enum SolarLightingModel {
    /// Returns a normalized scene-space direction that points from Earth to the Sun.
    nonisolated static func sceneSunDirection(at date: Date) -> SIMD3<Float> {
        let julianDate = date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
        let daysSinceJ2000 = julianDate - 2_451_545.0

        let meanLongitudeDegrees = normalizeDegrees(280.460 + 0.9856474 * daysSinceJ2000)
        let meanAnomalyDegrees = normalizeDegrees(357.528 + 0.9856003 * daysSinceJ2000)
        let meanAnomalyRadians = meanAnomalyDegrees * .pi / 180.0

        let eclipticLongitudeDegrees = meanLongitudeDegrees
            + 1.915 * sin(meanAnomalyRadians)
            + 0.020 * sin(2.0 * meanAnomalyRadians)
        let eclipticLongitudeRadians = eclipticLongitudeDegrees * .pi / 180.0
        let obliquityRadians = (23.439 - 0.0000004 * daysSinceJ2000) * .pi / 180.0

        let rightAscension = normalizeRadians(
            atan2(
                cos(obliquityRadians) * sin(eclipticLongitudeRadians),
                cos(eclipticLongitudeRadians)
            )
        )
        let declination = asin(sin(obliquityRadians) * sin(eclipticLongitudeRadians))

        let gmst = EarthCoordinateConverter.gmstRadians(for: date)
        let subsolarLongitudeRadians = normalizeRadians(rightAscension - gmst)
        let subsolarLatitudeRadians = declination

        let scenePosition = GlobeCoordinateConverter.scenePosition(
            latitudeDegrees: subsolarLatitudeRadians * 180.0 / .pi,
            longitudeDegrees: subsolarLongitudeRadians * 180.0 / .pi,
            altitudeKm: 0
        )
        let sunDirection = SIMD3<Float>(
            Float(scenePosition.x),
            Float(scenePosition.y),
            Float(scenePosition.z)
        )
        let length = simd_length(sunDirection)
        guard length > .ulpOfOne else {
            return SIMD3<Float>(0, 0, 1)
        }
        return sunDirection / length
    }

    /// Normalizes an angle to [0, 360) degrees.
    nonisolated private static func normalizeDegrees(_ degrees: Double) -> Double {
        var normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0 {
            normalized += 360.0
        }
        return normalized
    }

    /// Normalizes an angle to [0, 2π) radians.
    nonisolated private static func normalizeRadians(_ radians: Double) -> Double {
        var normalized = radians.truncatingRemainder(dividingBy: 2.0 * .pi)
        if normalized < 0 {
            normalized += 2.0 * .pi
        }
        return normalized
    }
}
