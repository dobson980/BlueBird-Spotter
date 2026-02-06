//
//  ContentView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import SwiftUI

/// Root container that switches between TLE listing and live tracking.
///
/// Tabs make it easy to compare raw TLE data with derived positions.
struct ContentView: View {
    /// Shared navigation state lets any tab route focus to the globe.
    @State private var navigationState: AppNavigationState
    /// View model for the TLE list tab.
    @State private var tleViewModel: CelesTrakViewModel
    /// View model for the tracking list tab.
    @State private var trackingViewModel: TrackingViewModel
    /// Independent tracking view model for the globe tab.
    ///
    /// This keeps each tab's lifecycle predictable when users switch tabs quickly.
    @State private var globeTrackingViewModel: TrackingViewModel

    /// Builds feature view models from a single app-level composition root.
    ///
    /// The optional `initialTab` argument is mainly useful for Xcode previews,
    /// where contributors often want to open a specific tab immediately.
    @MainActor
    init(
        compositionRoot: AppCompositionRoot = .live,
        initialTab: AppTab = .tles
    ) {
        let navigationState = AppNavigationState()
        navigationState.selectedTab = initialTab
        _navigationState = State(initialValue: navigationState)
        _tleViewModel = State(initialValue: compositionRoot.makeTLEViewModel())
        _trackingViewModel = State(initialValue: compositionRoot.makeTrackingViewModel())
        _globeTrackingViewModel = State(initialValue: compositionRoot.makeTrackingViewModel())
    }

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            // The TLE tab keeps the original list-based UI intact.
            TLEListView(viewModel: tleViewModel)
                .tabItem {
                    Label("TLEs", systemImage: "list.bullet")
                }
                .tag(AppTab.tles)

            // The tracking tab shows 1Hz orbital updates.
            TrackingView(viewModel: trackingViewModel)
                .tabItem {
                    Label("Tracking", systemImage: "location.north.circle")
                }
                .tag(AppTab.tracking)

            // The globe tab visualizes satellite positions around Earth.
            GlobeView(viewModel: globeTrackingViewModel)
                .tabItem {
                    Label("Globe", systemImage: "globe.americas.fill")
                }
                .tag(AppTab.globe)

            // The inside tab explains ASTS context and app behavior in simple language.
            InsideASTSView()
                .tabItem {
                    Label("Info", systemImage: "info.circle.fill")
                }
                .tag(AppTab.insideASTS)
        }
        // Let tab content flow under the tab bar so it feels like a floating glass overlay.
        .ignoresSafeArea(.container, edges: .bottom)
        .environment(navigationState)
    }
}

/// Preview for validating the default TLE tab composition.
#Preview("TLE Tab") {
    ContentView(initialTab: .tles)
}

/// Preview for validating tracking tab shell composition.
#Preview("Tracking Tab") {
    ContentView(initialTab: .tracking)
}

/// Preview for validating globe tab shell composition.
#Preview("Globe Tab") {
    ContentView(initialTab: .globe)
}

/// Preview for validating the information tab shell composition.
#Preview("Info Tab") {
    ContentView(initialTab: .insideASTS)
}
