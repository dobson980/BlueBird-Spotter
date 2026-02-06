//
//  GlobeOrbitPathBuilderTests.swift
//  BlueBird SpotterTests
//
//  Created by Codex on 2/6/26.
//

import Foundation
import Testing
import simd
@testable import BlueBird_Spotter

/// Unit tests for pure orbit-path generation logic.
///
/// These tests validate geometry inputs without rendering SceneKit views,
/// which keeps failures fast and deterministic.
struct GlobeOrbitPathBuilderTests {
    /// Creates a test satellite with a valid TLE pair.
    private func makeSatellite(line2: String = "2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456") -> Satellite {
        Satellite(
            id: 1,
            name: "TEST-SAT",
            tleLine1: "1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991",
            tleLine2: line2,
            epoch: nil
        )
    }

    /// Confirms all-mode sampling scales down as orbit count increases.
    @Test func effectiveSampleCount_scalesForLargeConstellations() {
        #expect(GlobeOrbitPathBuilder.effectiveSampleCount(for: .all, desiredCount: 10, baseSampleCount: 240) == 240)
        #expect(GlobeOrbitPathBuilder.effectiveSampleCount(for: .all, desiredCount: 80, baseSampleCount: 240) == 120)
        #expect(GlobeOrbitPathBuilder.effectiveSampleCount(for: .all, desiredCount: 200, baseSampleCount: 240) == 60)
        #expect(GlobeOrbitPathBuilder.effectiveSampleCount(for: .selectedOnly, desiredCount: 200, baseSampleCount: 240) == 240)
    }

    /// Confirms generated paths contain sampleCount points plus a closing point.
    @Test func buildOrbitPathVertices_closesLoopWithExpectedCount() {
        let vertices = GlobeOrbitPathBuilder.buildOrbitPathVertices(
            for: makeSatellite(),
            referenceDate: Date(timeIntervalSince1970: 1_000),
            sampleCount: 24,
            altitudeOffsetKm: 0
        )

        #expect(vertices.count == 25)
        #expect(vertices.first == vertices.last)
    }

    /// Confirms invalid sample counts or malformed TLEs return no vertices.
    @Test func buildOrbitPathVertices_returnsEmptyOnInvalidInputs() {
        let tooFewSamples = GlobeOrbitPathBuilder.buildOrbitPathVertices(
            for: makeSatellite(),
            referenceDate: Date(timeIntervalSince1970: 1_000),
            sampleCount: 1,
            altitudeOffsetKm: 0
        )
        #expect(tooFewSamples.isEmpty)

        let malformedMeanMotion = GlobeOrbitPathBuilder.buildOrbitPathVertices(
            for: makeSatellite(line2: "2 00001 SHORT"),
            referenceDate: Date(timeIntervalSince1970: 1_000),
            sampleCount: 24,
            altitudeOffsetKm: 0
        )
        #expect(malformedMeanMotion.isEmpty)
    }

    /// Confirms positive altitude offset pulls the drawn path closer to Earth.
    @Test func buildOrbitPathVertices_altitudeOffsetContractsRadius() {
        let base = GlobeOrbitPathBuilder.buildOrbitPathVertices(
            for: makeSatellite(),
            referenceDate: Date(timeIntervalSince1970: 1_000),
            sampleCount: 48,
            altitudeOffsetKm: 0
        )
        let offset = GlobeOrbitPathBuilder.buildOrbitPathVertices(
            for: makeSatellite(),
            referenceDate: Date(timeIntervalSince1970: 1_000),
            sampleCount: 48,
            altitudeOffsetKm: 100
        )

        #expect(base.count == offset.count)
        #expect(!base.isEmpty)

        let baseAverage = base.dropLast().map(simd_length).reduce(0, +) / Float(max(1, base.count - 1))
        let offsetAverage = offset.dropLast().map(simd_length).reduce(0, +) / Float(max(1, offset.count - 1))

        #expect(offsetAverage < baseAverage)
    }
}
