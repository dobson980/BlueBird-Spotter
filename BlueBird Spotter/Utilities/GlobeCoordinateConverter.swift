//
//  GlobeCoordinateConverter.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import Foundation
import SceneKit

/// Converts geodetic coordinates into SceneKit-friendly cartesian positions.
///
/// The conversion assumes a spherical Earth for visualization and scales
/// kilometers into SceneKit units to keep the globe manageable.
struct GlobeCoordinateConverter {
    /// WGS84 mean Earth radius used for the visualization.
    nonisolated static let earthRadiusKm: Double = 6371.0
    /// Default scale so 1 SceneKit unit equals Earth's radius.
    nonisolated static let defaultScale: Double = 1.0 / earthRadiusKm

    /// Converts latitude/longitude/altitude into a cartesian position.
    ///
    /// Marked `nonisolated` so math can run off the main actor in tests and rendering.
    ///
    /// - Parameters:
    ///   - latitudeDegrees: Geodetic latitude in degrees.
    ///   - longitudeDegrees: Geodetic longitude in degrees.
    ///   - altitudeKm: Altitude above mean Earth radius in kilometers.
    ///   - earthRadiusKm: Optional override for Earth's radius.
    ///   - scale: Scale factor converting kilometers to SceneKit units.
    /// - Returns: A cartesian position in SceneKit units.
    nonisolated static func scenePosition(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        altitudeKm: Double,
        earthRadiusKm: Double = earthRadiusKm,
        scale: Double = defaultScale
    ) -> SIMD3<Double> {
        let lat = latitudeDegrees * .pi / 180.0
        // Use east-positive longitude so 90E maps to the +X axis in SceneKit.
        let lon = longitudeDegrees * .pi / 180.0
        let radius = (earthRadiusKm + altitudeKm) * scale

        let x = radius * cos(lat) * sin(lon)
        let y = radius * sin(lat)
        let z = radius * cos(lat) * cos(lon)

        return SIMD3<Double>(x, y, z)
    }

    /// Converts a geodetic `SatellitePosition` into a SceneKit position.
    ///
    /// Coordinate convention: +Y is north, +Z is lon 0, and +X is lon 90E.
    nonisolated static func scenePosition(
        from position: SatellitePosition,
        earthRadiusScene: Float
    ) -> SCNVector3 {
        let lat = position.latitudeDegrees * .pi / 180.0
        let lon = position.longitudeDegrees * .pi / 180.0
        let altitudeScale = earthRadiusScene / Float(earthRadiusKm)
        let radius = earthRadiusScene + Float(position.altitudeKm) * altitudeScale

        let x = radius * Float(cos(lat) * sin(lon))
        let y = radius * Float(sin(lat))
        let z = radius * Float(cos(lat) * cos(lon))

        return SCNVector3(x, y, z)
    }

    /// Converts a TEME-frame velocity into a scene-space direction vector.
    ///
    /// The velocity is transformed from ECI (TEME) to the scene coordinate system
    /// and normalized for use as a direction. The scene convention is:
    /// +Y is north pole, +Z is prime meridian (lon 0), +X is lon 90E.
    ///
    /// - Parameters:
    ///   - velocityKmPerSec: Velocity in km/s (TEME frame).
    ///   - at: The date for Earth rotation (GMST) calculation.
    /// - Returns: A normalized direction vector in scene coordinates.
    nonisolated static func sceneVelocityDirection(
        from velocityKmPerSec: SIMD3<Double>,
        at date: Date
    ) -> SIMD3<Float> {
        // TEME to ECEF rotation (same as position conversion in EarthCoordinateConverter).
        let gmst = EarthCoordinateConverter.gmstRadians(for: date)
        let cosGmst = cos(gmst)
        let sinGmst = sin(gmst)

        // Rotate velocity from TEME (ECI) to ECEF.
        let ecefX = velocityKmPerSec.x * cosGmst + velocityKmPerSec.y * sinGmst
        let ecefY = -velocityKmPerSec.x * sinGmst + velocityKmPerSec.y * cosGmst
        let ecefZ = velocityKmPerSec.z

        // ECEF to SceneKit: ECEF uses X toward lon 0, Y toward lon 90E, Z toward north.
        // SceneKit uses X toward lon 90E, Y toward north, Z toward lon 0.
        let sceneX = Float(ecefY)   // ECEF Y (lon 90E) -> Scene X
        let sceneY = Float(ecefZ)   // ECEF Z (north) -> Scene Y
        let sceneZ = Float(ecefX)   // ECEF X (lon 0) -> Scene Z

        let velocity = SIMD3<Float>(sceneX, sceneY, sceneZ)
        let length = simd_length(velocity)
        guard length > 0 else { return SIMD3<Float>(0, 0, 1) }
        return velocity / length
    }
}
