//
//  CelesTrakJSONTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Validates JSON decoding and mapping into the existing TLE model.
struct CelesTrakJSONTests {

    private enum FixtureError: Error {
        case missingFixture
    }

    /// Loads the on-disk JSON fixture stored alongside the tests.
    private func loadFixtureData(named name: String) throws -> Data {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixtureURL = testDirectory.appendingPathComponent("Fixtures").appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw FixtureError.missingFixture
        }
        return try Data(contentsOf: fixtureURL)
    }

    /// Decodes the fixture and maps it back into display-ready TLEs.
    @Test @MainActor func jsonFixture_decodesIntoTLEs() throws {
        let data = try loadFixtureData(named: "CelesTrakGPFixture")
        let records = try JSONDecoder().decode([CelesTrakGPRecord].self, from: data)
        let tles = records.compactMap { $0.asTLE() }

        #expect(tles.count == 2)
        #expect(tles.first?.name == "BLUEBIRD-1")
        #expect(tles.first?.line1.hasPrefix("1 54001") == true)
        #expect(tles.last?.name == "BLUEBIRD-2")
    }
}
