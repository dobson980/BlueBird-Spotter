//
//  GlobeDebugFlags.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/26/25.
//

import Foundation

/// Centralizes globe-only debug flags so release builds stay clean.
enum GlobeDebugFlags {
    #if DEBUG
    /// Shows the tuning panel for live tweaking when explicitly enabled.
    static var showTuningUI: Bool {
        ProcessInfo.processInfo.environment["GLOBE_DEBUG_UI"] == "1"
    }
    /// Shows the coordinate debug markers for orientation validation when enabled.
    static var showDebugMarkers: Bool {
        ProcessInfo.processInfo.environment["GLOBE_DEBUG_MARKERS"] == "1"
    }
    /// Shows basic render statistics to diagnose missing scene content.
    static var showRenderStats: Bool {
        ProcessInfo.processInfo.environment["GLOBE_DEBUG_STATS"] == "1"
    }
    #else
    /// Hides debug UI in production.
    static let showTuningUI = false
    /// Hides debug markers in production.
    static let showDebugMarkers = false
    /// Hides render stats in production.
    static let showRenderStats = false
    #endif
}
