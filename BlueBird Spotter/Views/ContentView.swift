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
    @State private var navigationState = AppNavigationState()

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            // The TLE tab keeps the original list-based UI intact.
            TLEListView()
                .tabItem {
                    Label("TLEs", systemImage: "list.bullet")
                }
                .tag(AppTab.tles)

            // The tracking tab shows 1Hz orbital updates.
            TrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "location.north.circle")
                }
                .tag(AppTab.tracking)

            // The globe tab visualizes satellite positions around Earth.
            GlobeView()
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

/// Preview for quickly checking load-state layout in Xcode.
#Preview {
    ContentView()
}
