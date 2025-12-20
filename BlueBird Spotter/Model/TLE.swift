//
//  TLE.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation

struct TLE: Sendable, Equatable {
    let name: String?     // Title line if present
    let line1: String     // Must start with "1 "
    let line2: String     // Must start with "2 "
}
