//
//  EarthCoordinateConverter.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import simd

/// Converts between TEME/ECI coordinates and WGS84 geodetic coordinates.
///
/// These helpers stay small and pure so the propagation layer can focus on
/// orbital math while the UI consumes friendly latitude/longitude values.
struct EarthCoordinateConverter {
    /// Represents a WGS84 coordinate in degrees with altitude in kilometers.
    struct GeodeticCoordinate: Sendable, Equatable {
        let latitudeDegrees: Double
        let longitudeDegrees: Double
        let altitudeKm: Double
    }

    /// Converts TEME/ECI position to a WGS84 geodetic coordinate at a given time.
    ///
    /// Nonisolated so propagation can run off the main actor.
    nonisolated static func temeToGeodetic(position: SIMD3<Double>, at date: Date) -> GeodeticCoordinate {
        let ecefPosition = temeToEcef(position: position, at: date)
        return ecefToGeodetic(position: ecefPosition)
    }

    /// Rotates TEME/ECI coordinates into ECEF using the GMST for the given date.
    nonisolated static func temeToEcef(position: SIMD3<Double>, at date: Date) -> SIMD3<Double> {
        let gmst = gmstRadians(for: date)
        let cosGmst = cos(gmst)
        let sinGmst = sin(gmst)

        let x = cosGmst * position.x + sinGmst * position.y
        let y = -sinGmst * position.x + cosGmst * position.y
        let z = position.z

        return SIMD3(x, y, z)
    }

    /// Converts an ECEF position into WGS84 latitude, longitude, and altitude.
    nonisolated static func ecefToGeodetic(position: SIMD3<Double>) -> GeodeticCoordinate {
        let x = position.x
        let y = position.y
        let z = position.z

        let semiMajorAxisKm = 6378.137
        let flattening = 1.0 / 298.257223563
        let eccentricitySquared = flattening * (2.0 - flattening)

        let longitude = atan2(y, x)
        let horizontalDistance = hypot(x, y)

        var latitude = atan2(z, horizontalDistance)
        for _ in 0..<5 {
            let sinLat = sin(latitude)
            let radiusOfCurvature = semiMajorAxisKm / sqrt(1.0 - eccentricitySquared * sinLat * sinLat)
            latitude = atan2(z + eccentricitySquared * radiusOfCurvature * sinLat, horizontalDistance)
        }

        let sinLat = sin(latitude)
        let radiusOfCurvature = semiMajorAxisKm / sqrt(1.0 - eccentricitySquared * sinLat * sinLat)
        let altitudeKm = horizontalDistance / cos(latitude) - radiusOfCurvature

        return GeodeticCoordinate(
            latitudeDegrees: latitude * 180.0 / Double.pi,
            longitudeDegrees: normalizeLongitudeDegrees(longitude * 180.0 / Double.pi),
            altitudeKm: altitudeKm
        )
    }

    /// Computes the Greenwich Mean Sidereal Time in radians for a given date.
    ///
    /// Exposed so rendering code can align inertial orbital paths to Earth.
    nonisolated static func gmstRadians(for date: Date) -> Double {
        let julianDate = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let centuries = (julianDate - 2451545.0) / 36525.0
        let gmstSeconds = 67310.54841
            + (876600.0 * 3600.0 + 8640184.812866) * centuries
            + 0.093104 * centuries * centuries
            - 6.2e-6 * centuries * centuries * centuries
        let gmstRadians = (gmstSeconds.truncatingRemainder(dividingBy: 86400.0)) * (2.0 * Double.pi / 86400.0)
        return gmstRadians < 0.0 ? gmstRadians + 2.0 * Double.pi : gmstRadians
    }

    /// Keeps longitude in the [-180, 180] range for predictable UI display.
    nonisolated private static func normalizeLongitudeDegrees(_ degrees: Double) -> Double {
        var normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        if normalized > 180.0 {
            normalized -= 360.0
        } else if normalized < -180.0 {
            normalized += 360.0
        }
        return normalized
    }
}
