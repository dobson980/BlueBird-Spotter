//
//  BlueBird_SpotterApp.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import BackgroundTasks
import SwiftUI

/// Entry point for the BlueBird Spotter app.
///
/// The app launches directly into `ContentView`, which loads and presents
/// a list of TLEs so you can inspect the fetched satellite data.
@main
struct BlueBird_SpotterApp: App {
    /// Observes lifecycle changes to schedule background refresh work.
    @Environment(\.scenePhase) private var scenePhase
    /// Coordinates background task registration and scheduling.
    private let backgroundRefreshManager = TLEBackgroundRefreshManager.shared

    init() {
        // Register the background task handler before the app enters the foreground.
        backgroundRefreshManager.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            Task {
                await backgroundRefreshManager.scheduleIfNeeded(queryKey: "SPACEMOBILE")
            }
        }
    }
}
