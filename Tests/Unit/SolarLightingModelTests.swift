//
//  SolarLightingModelTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 2/6/26.
//

import Foundation
import Testing
import simd
@testable import BlueBird_Spotter

/// Unit tests for UTC-driven sunlight direction math.
///
/// These checks catch regressions that would otherwise look like subtle lighting
/// drift in the 3D globe.
struct SolarLightingModelTests {
    /// Confirms direction vectors are finite and normalized.
    @Test func sceneSunDirection_isNormalized() {
        let direction = SolarLightingModel.sceneSunDirection(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(direction.x.isFinite)
        #expect(direction.y.isFinite)
        #expect(direction.z.isFinite)

        let length = simd_length(direction)
        #expect(abs(length - 1) < 0.0001)
    }

    /// Confirms sunlight direction changes as Earth rotates over time.
    @Test func sceneSunDirection_changesAcrossTime() {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let later = reference.addingTimeInterval(12 * 60 * 60)

        let first = SolarLightingModel.sceneSunDirection(at: reference)
        let second = SolarLightingModel.sceneSunDirection(at: later)

        #expect(simd_distance(first, second) > 0.001)
    }
}
