//
//  BlueBird_SpotterTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/19/25.
//

import Testing
@testable import BlueBird_Spotter

struct BlueBird_SpotterTests {

    private struct StubTLEService: CelesTrakTLEService {
        let tles: [TLE]

        func fetchTLEs(nameQuery: String) async throws -> [TLE] {
            tles
        }

        nonisolated static func parseTLEText(_ text: String) throws -> [TLE] {
            try CelesTrakTLE.parseTLEText(text)
        }
    }

    @Test func parseTLEText_filtersDebrisAndParsesThreeLine() async throws {
        let text = """
        BLUEBIRD-1
        1 12345U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 12345  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        BLUEBIRD DEB
        1 67890U 98067B   20344.12345678  .00001234  00000-0  10270-3 0  9992
        2 67890  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123457
        """

        let tles = try CelesTrakTLE.parseTLEText(text)

        #expect(tles.count == 1)
        #expect(tles.first?.name == "BLUEBIRD-1")
    }

    @Test func parseTLEText_allowsTwoLineFormat() async throws {
        let text = """
        1 25544U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 25544  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        """

        let tles = try CelesTrakTLE.parseTLEText(text)

        #expect(tles.count == 1)
        #expect(tles.first?.name == nil)
    }

    @Test func viewModel_sortsTLEsByName() async throws {
        let stub = StubTLEService(tles: [
            TLE(name: "Zulu", line1: "1 Z", line2: "2 Z"),
            TLE(name: "alpha", line1: "1 A", line2: "2 A"),
            TLE(name: nil, line1: "1 N", line2: "2 N"),
        ])
        let viewModel = await MainActor.run { CelesTrakViewModel(service: stub) }

        await viewModel.fetchTLEs(nameQuery: "BLUEBIRD")

        #expect(viewModel.tles.map { $0.name } == ["alpha", "Zulu", nil])
    }

}
