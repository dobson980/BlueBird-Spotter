//
//  TLE.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
/// Represents a single TLE record with optional name and two data lines.
struct TLE: Sendable, Equatable {
    /// Optional title line from 3-line TLE format.
    let name: String?
    /// First data line, expected to start with "1 ".
    let line1: String
    /// Second data line, expected to start with "2 ".
    let line2: String
}
