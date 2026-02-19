//
//  SatelliteIDParserTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 2/6/26.
//

import Testing
@testable import BlueBird_Spotter

/// Unit tests for NORAD id parsing helpers.
///
/// Stable parsing is important because navigation and selection use this id.
struct SatelliteIDParserTests {
    /// Confirms parser extracts a standard NORAD id from TLE line 1.
    @Test @MainActor func parseNoradId_extractsValue() {
        let line1 = "1 25544U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991"
        #expect(SatelliteIDParser.parseNoradId(line1: line1) == 25544)
    }

    /// Confirms parser trims inner spaces in the id column.
    @Test @MainActor func parseNoradId_trimsWhitespace() {
        let line1 = "1  1234U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991"
        #expect(SatelliteIDParser.parseNoradId(line1: line1) == 1234)
    }

    /// Confirms parser returns nil when line 1 is too short.
    @Test @MainActor func parseNoradId_returnsNilForShortLine() {
        #expect(SatelliteIDParser.parseNoradId(line1: "1 12") == nil)
    }
}
