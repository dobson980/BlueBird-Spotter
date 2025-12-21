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
        }
    }
}

/// Preview for quickly checking load-state layout in Xcode.
#Preview {
    ContentView()
}
