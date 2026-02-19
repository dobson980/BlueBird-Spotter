//
//  AppAppearanceMode.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
//

import SwiftUI

/// Controls how the app resolves light and dark appearance.
///
/// Why this exists:
/// - The globe settings panel needs one app-wide source of truth for appearance.
/// - We persist the user's preference so launches are consistent.
///
/// What this does NOT do:
/// - It does not read or write storage directly.
/// - It does not own UI layout for the settings panel.
enum AppAppearanceMode: String, CaseIterable, Identifiable {
    /// Follow the current system light/dark setting.
    case system
    /// Force the entire app into light mode.
    case light
    /// Force the entire app into dark mode.
    case dark

    var id: String { rawValue }

    /// Short label used in segmented controls.
    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    /// Converts the stored preference into SwiftUI's optional override model.
    ///
    /// Returning `nil` means "use system", which is exactly what we want for default behavior.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
