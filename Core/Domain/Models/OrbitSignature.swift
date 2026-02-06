//
//  OrbitSignature.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/3/26.
//

import Foundation

/// Represents the shared orbital characteristics used to dedupe paths.
///
/// Mean anomaly is intentionally excluded so satellites in the same plane
/// and shape can reuse a single orbital path.
struct OrbitSignature: Hashable, Sendable {
    /// Rounds angular values (degrees) so near-identical planes share a single path.
    private static let anglePrecision: Double = 1e2
    /// Rounds eccentricity to merge visually similar orbits.
    private static let eccentricityPrecision: Double = 1e4
    /// Rounds mean motion to group satellites with nearly identical periods.
    private static let meanMotionPrecision: Double = 1e2

    let inclination: Double
    let raan: Double
    let eccentricity: Double
    let argumentOfPerigee: Double
    let meanMotion: Double

    /// Builds a signature from the second TLE line using fixed column ranges.
    init?(tleLine2: String) {
        guard let inclination = Self.parseDouble(from: tleLine2, range: 9...16),
              let raan = Self.parseDouble(from: tleLine2, range: 18...25),
              let eccentricity = Self.parseEccentricity(from: tleLine2, range: 27...33),
              let argumentOfPerigee = Self.parseDouble(from: tleLine2, range: 35...42),
              let meanMotion = Self.parseDouble(from: tleLine2, range: 53...63) else {
            return nil
        }

        self.inclination = Self.rounded(inclination, precision: Self.anglePrecision)
        self.raan = Self.rounded(raan, precision: Self.anglePrecision)
        self.eccentricity = Self.rounded(eccentricity, precision: Self.eccentricityPrecision)
        self.argumentOfPerigee = Self.rounded(argumentOfPerigee, precision: Self.anglePrecision)
        self.meanMotion = Self.rounded(meanMotion, precision: Self.meanMotionPrecision)
    }

    /// Quantizes values so small parsing differences don't produce new signatures.
    private static func rounded(_ value: Double, precision: Double = 1e4) -> Double {
        (value * precision).rounded() / precision
    }

    /// Parses a double from a fixed-range substring in the TLE line.
    private static func parseDouble(from line: String, range: ClosedRange<Int>) -> Double? {
        guard line.count >= range.upperBound else { return nil }
        let start = line.index(line.startIndex, offsetBy: range.lowerBound - 1)
        let end = line.index(line.startIndex, offsetBy: range.upperBound - 1)
        let substring = line[start...end].trimmingCharacters(in: .whitespaces)
        return Double(substring)
    }

    /// Parses eccentricity, which is stored as 7 digits without a decimal point.
    private static func parseEccentricity(from line: String, range: ClosedRange<Int>) -> Double? {
        guard line.count >= range.upperBound else { return nil }
        let start = line.index(line.startIndex, offsetBy: range.lowerBound - 1)
        let end = line.index(line.startIndex, offsetBy: range.upperBound - 1)
        let substring = line[start...end].trimmingCharacters(in: .whitespaces)
        guard let digits = Double(substring) else { return nil }
        return digits / 1_000_0000.0
    }
}
