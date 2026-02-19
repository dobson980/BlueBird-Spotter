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
/// feature tabs using a centralized app composition root.
@main
struct BlueBird_SpotterApp: App {
    /// Observes lifecycle changes to schedule background refresh work.
    @Environment(\.scenePhase) private var scenePhase
    /// Persists the app-wide appearance preference selected from globe settings.
    @AppStorage("app.appearance.mode") private var appAppearanceModeRaw = AppAppearanceMode.system.rawValue
    /// Coordinates background task registration and scheduling.
    private let backgroundRefreshManager = TLEBackgroundRefreshManager.shared

    init() {
        // Register the background task handler before the app enters the foreground.
        backgroundRefreshManager.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(compositionRoot: .live)
                .preferredColorScheme(appAppearanceMode.preferredColorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            Task {
                await backgroundRefreshManager.scheduleIfNeeded(queryKey: "SPACEMOBILE")
            }
        }
    }

    /// Resolves persisted raw storage into a safe enum value.
    private var appAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appAppearanceModeRaw) ?? .system
    }
}
