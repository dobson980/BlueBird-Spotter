//
//  TLECacheStoreTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Unit tests for cache persistence and corruption handling.
struct TLECacheStoreTests {

    /// Saves a record and confirms it can be loaded back intact.
    @Test @MainActor func cacheStore_savesAndLoadsRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TLECacheStore(directory: directory)
        let fetchedAt = Date(timeIntervalSince1970: 12345)
        let sourceURL = URL(string: "https://example.com")!
        let payload = Data("TLE TEXT".utf8)

        try await store.save(
            queryKey: "SPACEMOBILE",
            payload: payload,
            sourceURL: sourceURL,
            fetchedAt: fetchedAt,
            contentType: "text/tle"
        )
        let record = try await store.load(queryKey: "SPACEMOBILE")

        #expect(record?.payload == payload)
        #expect(
            record?.metadata == TLECacheMetadata(
                queryKey: "SPACEMOBILE",
                fetchedAt: fetchedAt,
                sourceURL: sourceURL,
                contentType: "text/tle",
                etag: nil,
                lastModified: nil
            )
        )
    }

    /// Returns nil when metadata is unreadable even if payload exists.
    @Test @MainActor func cacheStore_returnsNilWhenMetadataIsCorrupt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TLECacheStore(directory: directory)
        let metadataURL = directory.appendingPathComponent("SPACEMOBILE.json")
        let payloadURL = directory.appendingPathComponent("SPACEMOBILE.dat")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: metadataURL, options: .atomic)
        try Data("TLE TEXT".utf8).write(to: payloadURL, options: .atomic)

        let record = try await store.load(queryKey: "SPACEMOBILE")

        #expect(record == nil)
    }

    /// Migrates legacy .tle payloads into the new data-backed cache format.
    @Test @MainActor func cacheStore_migratesLegacyTextPayload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TLECacheStore(directory: directory)
        let metadataURL = directory.appendingPathComponent("SPACEMOBILE.json")
        let legacyURL = directory.appendingPathComponent("SPACEMOBILE.tle")
        let payloadURL = directory.appendingPathComponent("SPACEMOBILE.dat")
        let fetchedAt = Date(timeIntervalSince1970: 12345)
        let sourceURL = URL(string: "https://example.com")!

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyMetadata: [String: Any] = [
            "queryKey": "SPACEMOBILE",
            "fetchedAt": ISO8601DateFormatter().string(from: fetchedAt),
            "sourceURL": sourceURL.absoluteString
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: legacyMetadata, options: [])
        try metadataData.write(to: metadataURL, options: .atomic)
        try Data("LEGACY TLE".utf8).write(to: legacyURL, options: .atomic)

        let record = try await store.load(queryKey: "SPACEMOBILE")

        #expect(record?.payload == Data("LEGACY TLE".utf8))
        #expect(FileManager.default.fileExists(atPath: payloadURL.path))
    }
}
