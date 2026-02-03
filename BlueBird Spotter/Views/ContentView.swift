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
    var body: some View {
        TabView {
            // The TLE tab keeps the original list-based UI intact.
            TLEListView()
                .tabItem {
                    Label("TLEs", systemImage: "list.bullet")
                }

            // The tracking tab shows 1Hz orbital updates.
            TrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "location.north.circle")
                }

            // The globe tab visualizes satellite positions around Earth.
            GlobeView()
                .tabItem {
                    Label("Globe", systemImage: "globe.americas.fill")
                }
        }
        // Let tab content flow under the tab bar so it feels like a floating glass overlay.
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

/// Preview for quickly checking load-state layout in Xcode.
#Preview {
    ContentView()
}
