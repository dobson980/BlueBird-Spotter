//
//  AppDirectories.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation

/// Centralizes application directory resolution for on-disk storage.
struct AppDirectories {
    /// Returns (and creates) a subdirectory in Application Support.
    nonisolated static func applicationSupportSubdirectory(_ components: [String]) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = components.reduce(base) { partialResult, component in
            partialResult.appendingPathComponent(component, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
