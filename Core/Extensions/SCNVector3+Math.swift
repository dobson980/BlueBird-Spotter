//
//  SCNVector3+Math.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/26/25.
//

import SceneKit
import simd

/// Adds lightweight vector math helpers for SceneKit coordinate work.
extension SCNVector3 {
    /// Length of the vector in scene units.
    var length: Float {
        sqrt(x * x + y * y + z * z)
    }

    /// Returns a unit-length version of the vector when possible.
    var normalized: SCNVector3 {
        let value = length
        guard value > 0 else { return SCNVector3Zero }
        return self * (1 / value)
    }

    /// Dot product between two vectors.
    func dot(_ other: SCNVector3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    /// Cross product between two vectors.
    func cross(_ other: SCNVector3) -> SCNVector3 {
        SCNVector3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    /// SIMD representation for interop with simd quaternions.
    var simd: SIMD3<Float> {
        SIMD3(x, y, z)
    }

    /// Builds a SceneKit vector from a SIMD value.
    init(_ simdValue: SIMD3<Float>) {
        self.init(simdValue.x, simdValue.y, simdValue.z)
    }

    /// Adds two vectors.
    static func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    /// Subtracts two vectors.
    static func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    /// Scales a vector by a scalar value.
    static func *(lhs: SCNVector3, rhs: Float) -> SCNVector3 {
        SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
}
