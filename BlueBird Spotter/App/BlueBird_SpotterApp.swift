//
//  BlueBird_SpotterApp.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import SwiftUI

/// Entry point for the BlueBird Spotter app.
///
/// The app launches directly into `ContentView`, which loads and presents
/// a list of TLEs so you can inspect the fetched satellite data.
@main
struct BlueBird_SpotterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
