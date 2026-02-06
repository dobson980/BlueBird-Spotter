//
//  Satellite.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation

/// Represents a satellite with stable identity and its source TLE lines.
///
/// This model keeps the NORAD catalog number alongside the TLE so other
/// subsystems (like orbit computation) can derive deterministic behavior.
struct Satellite: Sendable, Equatable, Identifiable {
    /// NORAD catalog number used as a stable identifier across sessions.
    let id: Int
    let name: String
    let tleLine1: String
    let tleLine2: String
    /// Epoch from the source dataset when available.
    let epoch: Date?
}
