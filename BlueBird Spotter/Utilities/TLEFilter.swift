//
//  TLEFilter.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

/// Utility filters to prune unwanted TLEs.
enum TLEFilter {
    /// Removes entries that look like debris based on the name.
    nonisolated static func excludeDebris(from tles: [TLE]) -> [TLE] {
        tles.filter { tle in
            guard let name = tle.name else { return true }
            return !name.uppercased().contains("DEB")
        }
    }
}
