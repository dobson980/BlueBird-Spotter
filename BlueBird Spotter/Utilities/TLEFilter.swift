//
//  TLEFilter.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

enum TLEFilter {
    nonisolated static func excludeDebris(from tles: [TLE]) -> [TLE] {
        tles.filter { tle in
            guard let name = tle.name else { return true }
            return !name.uppercased().contains("DEB")
        }
    }
}
