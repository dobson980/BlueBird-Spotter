//
//  OrbitPathMode.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/3/26.
//

import Foundation

/// Defines which orbital paths should be rendered on the globe.
enum OrbitPathMode: String, CaseIterable, Identifiable {
    /// Do not render any orbital paths.
    case off
    /// Render only the selected satellite's orbital path.
    case selectedOnly
    /// Render orbital paths for all unique orbits.
    case all

    var id: String { rawValue }

    /// Human-friendly label used in the settings picker.
    var label: String {
        switch self {
        case .off:
            return "Off"
        case .selectedOnly:
            return "Selected"
        case .all:
            return "All"
        }
    }
}
