//
//  CelesTrakTLEService.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

/// Defines the core capabilities for fetching and parsing TLEs.
protocol CelesTrakTLEService: Sendable {
    /// Fetches raw payload data for the given query key.
    func fetchTLEText(nameQuery: String, cacheMetadata: TLECacheMetadata?) async throws -> TLEFetchResult
    /// Fetches and parses TLEs for the given query key.
    func fetchTLEs(nameQuery: String) async throws -> [TLE]
    /// Parses raw TLE text into structured models.
    nonisolated static func parseTLEText(_ text: String) throws -> [TLE]
}
