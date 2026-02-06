//
//  BlueBird_SpotterTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Unit tests that validate parsing and view model behavior.
struct BlueBird_SpotterTests {

    /// Confirms name + two lines are parsed as a 3-line TLE.
    @Test @MainActor func parseTLEText_parsesThreeLineFormat() async throws {
        let text = """
        BLUEBIRD-1
        1 12345U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 12345  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        """

        let tles = try CelesTrakTLEClient.parseTLEText(text)

        #expect(tles.count == 1)
        #expect(tles.first?.name == "BLUEBIRD-1")
    }

    /// Confirms a 2-line TLE parses without a name.
    @Test @MainActor func parseTLEText_allowsTwoLineFormat() async throws {
        let text = """
        1 25544U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 25544  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        """

        let tles = try CelesTrakTLEClient.parseTLEText(text)

        #expect(tles.count == 1)
        #expect(tles.first?.name == nil)
    }

    /// Confirms malformed input throws a typed parse error.
    @Test @MainActor func parseTLEText_throwsOnMalformedBlock() async throws {
        let text = """
        BLUEBIRD-2
        X 12345U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 12345  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        """

        do {
            _ = try CelesTrakTLEClient.parseTLEText(text)
            #expect(Bool(false))
        } catch let error as CelesTrakError {
            switch error {
            case .malformedTLE:
                #expect(Bool(true))
            default:
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
    }

    /// Confirms view model sorting uses case-insensitive name ordering.
    @Test @MainActor func viewModel_sortsTLEsByName() async throws {
        let result = TLERepositoryResult(
            tles: [
                TLE(name: "Zulu", line1: "1 Z", line2: "2 Z"),
                TLE(name: "alpha", line1: "1 A", line2: "2 A"),
                TLE(name: nil, line1: "1 N", line2: "2 N"),
            ],
            fetchedAt: Date(),
            source: .cache
        )
        let viewModel = CelesTrakViewModel(fetchHandler: { _ in result })

        await viewModel.fetchTLEs(nameQuery: "BLUEBIRD")

        #expect(viewModel.tles.map { $0.name } == ["alpha", "Zulu", nil])
    }

}
