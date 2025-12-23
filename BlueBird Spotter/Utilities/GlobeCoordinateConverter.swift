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
}
