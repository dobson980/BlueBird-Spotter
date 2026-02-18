//
//  SatelliteIDParser.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/4/26.
//

import Foundation

/// Parses satellite identifiers from raw TLE lines for navigation shortcuts.
enum SatelliteIDParser {
    /// Extracts the NORAD catalog id from TLE line 1, if present.
    nonisolated static func parseNoradId(line1: String) -> Int? {
        guard line1.count >= 7 else { return nil }
        let start = line1.index(line1.startIndex, offsetBy: 2)
        let end = line1.index(start, offsetBy: 5)
        let idString = line1[start..<end].trimmingCharacters(in: .whitespaces)
        return Int(idString)
    }
}
