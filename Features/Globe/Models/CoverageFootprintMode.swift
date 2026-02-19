//
//  CoverageFootprintMode.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/17/26.
//

import Foundation

/// Defines which satellite coverage footprints should be rendered on the globe.
enum CoverageFootprintMode: String, CaseIterable, Identifiable {
    /// Hide all coverage overlays.
    case off
    /// Render only the selected satellite's estimated footprint.
    case selectedOnly
    /// Render footprints for all tracked satellites.
    case all

    var id: String { rawValue }

    /// User-facing label used in segmented settings controls.
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
