//
//  TrackingSection.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import Foundation

/// Section model used by `TrackingView` to group satellites by program category.
///
/// Why this exists:
/// - Keeping the section model in `Models/` makes list grouping reusable.
/// - The view can stay focused on rendering and interaction.
struct TrackingSection: Identifiable {
    let category: SatelliteProgramCategory
    let satellites: [TrackedSatellite]

    var id: String { category.label }
}
