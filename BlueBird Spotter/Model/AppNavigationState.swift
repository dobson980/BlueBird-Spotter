//
//  AppNavigationState.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/4/26.
//

import Foundation
import Observation

/// Identifies the active tab so other views can trigger navigation.
enum AppTab: Hashable {
    case tles
    case tracking
    case globe
}

/// Represents a request to focus the globe camera on a specific satellite.
struct SatelliteFocusRequest: Equatable {
    /// NORAD catalog id for the satellite that should be focused.
    let satelliteId: Int
    /// Unique token so repeated taps on the same satellite still trigger updates.
    let token: UUID
}

/// Shared navigation state for cross-tab interactions.
///
/// Tapping a row in another tab can switch to the globe and request a camera focus.
@MainActor
@Observable
final class AppNavigationState {
    /// Current tab selection.
    var selectedTab: AppTab = .tles
    /// Latest camera focus request for the globe view.
    var focusRequest: SatelliteFocusRequest?

    /// Switches to the globe and requests a focus on the selected satellite.
    func focusOnSatellite(id: Int) {
        selectedTab = .globe
        focusRequest = SatelliteFocusRequest(satelliteId: id, token: UUID())
    }
}
