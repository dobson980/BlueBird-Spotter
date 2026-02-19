//
//  CelesTrakErrorTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 2/6/26.
//

import Testing
@testable import BlueBird_Spotter

/// Unit tests for user-facing error descriptions.
///
/// Keeping these strings stable helps keep UI messaging predictable.
struct CelesTrakErrorTests {
    /// Confirms status errors include the numeric HTTP code.
    @Test func errorDescription_includesStatusCode() {
        let description = CelesTrakError.badStatus(403).errorDescription
        #expect(description?.contains("403") == true)
    }

    /// Confirms malformed TLE errors include human-readable line numbers.
    @Test func errorDescription_malformedTLEUsesOneBasedLineNumbers() {
        let description = CelesTrakError.malformedTLE(atLine: 0, context: "Expected line").errorDescription
        #expect(description?.contains("line 1") == true)
    }

    /// Confirms not-modified errors explain missing cache context.
    @Test func errorDescription_notModifiedMentionsCache() {
        let description = CelesTrakError.notModified.errorDescription
        #expect(description?.contains("cached") == true)
    }
}
