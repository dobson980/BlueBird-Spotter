//
//  TLESection.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import Foundation

/// Section model used by `TLEListView` to group TLE rows by program category.
///
/// Keeping this out of the view body makes list grouping reusable and easier to test.
struct TLESection: Identifiable {
    let category: SatelliteProgramCategory
    let tles: [TLE]

    var id: String { category.label }
}
