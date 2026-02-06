//
//  TLECacheStore.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation

/// Metadata persisted alongside a raw TLE payload.
struct TLECacheMetadata: Equatable, Sendable {
    /// Maps the cache metadata fields for JSON encoding and decoding.
    enum CodingKeys: String, CodingKey {
        case queryKey
        case fetchedAt
        case sourceURL
        case contentType
        case etag
        case lastModified
    }

    let queryKey: String
    let fetchedAt: Date
    let sourceURL: URL
    /// Describes the payload format to support future JSON storage.
    let contentType: String
    /// HTTP ETag captured from the origin for conditional requests.
    let etag: String?
    /// HTTP Last-Modified captured from the origin for conditional requests.
    let lastModified: String?

    /// Designated initializer with a default content type for TLE text.
    nonisolated init(
        queryKey: String,
        fetchedAt: Date,
        sourceURL: URL,
        contentType: String = "text/tle",
        etag: String? = nil,
        lastModified: String? = nil
    ) {
        self.queryKey = queryKey
        self.fetchedAt = fetchedAt
        self.sourceURL = sourceURL
        self.contentType = contentType
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// Nonisolated Codable conformance keeps metadata usable off the main actor.
nonisolated extension TLECacheMetadata: Codable {
    /// Allows decoding legacy metadata that did not include a content type.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queryKey = try container.decode(String.self, forKey: .queryKey)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType) ?? "text/tle"
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
    }

    /// Encodes metadata fields to JSON for the on-disk cache.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(queryKey, forKey: .queryKey)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(contentType, forKey: .contentType)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
    }
}

/// Combined cache record returned to callers.
struct TLECacheRecord: Equatable, Sendable {
    let payload: Data
    let metadata: TLECacheMetadata
}

/// File-backed cache for raw TLE text and metadata.
actor TLECacheStore {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var didEnsureDirectory = false

    /// Test initializer allowing a custom directory.
    init(directory: URL) {
        self.directory = directory
        self.fileManager = .default
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Production initializer that targets Application Support.
    init() {
        do {
            let directory = try AppDirectories.applicationSupportSubdirectory(["BlueBirdSpotter", "TLECache"])
            self.init(directory: directory)
        } catch {
            preconditionFailure("Unable to resolve Application Support cache directory: \(error)")
        }
    }

    /// Loads a cached record, returning nil if missing or invalid.
    func load(queryKey: String) throws -> TLECacheRecord? {
        try ensureDirectoryExists()
        let urls = try cacheURLs(for: queryKey)
        guard fileManager.fileExists(atPath: urls.metadataURL.path) else {
            return nil
        }

        do {
            let metadataData = try Data(contentsOf: urls.metadataURL)
            let metadata = try decoder.decode(TLECacheMetadata.self, from: metadataData)
            let payloadData = try loadPayloadData(urls: urls)
            return TLECacheRecord(payload: payloadData, metadata: metadata)
        } catch {
            return nil
        }
    }

    /// Loads a cached text payload for the current parser when available.
    func loadTextPayload(queryKey: String) throws -> String? {
        guard let record = try load(queryKey: queryKey) else { return nil }
        return decodeTextPayload(record)
    }

    /// Saves raw payload data and metadata using atomic writes.
    func save(
        queryKey: String,
        payload: Data,
        sourceURL: URL,
        fetchedAt: Date,
        contentType: String,
        etag: String? = nil,
        lastModified: String? = nil
    ) throws {
        try ensureDirectoryExists()
        let urls = try cacheURLs(for: queryKey)
        let metadata = TLECacheMetadata(
            queryKey: queryKey,
            fetchedAt: fetchedAt,
            sourceURL: sourceURL,
            contentType: contentType,
            etag: etag,
            lastModified: lastModified
        )
        let metadataData = try encoder.encode(metadata)

        try metadataData.write(to: urls.metadataURL, options: .atomic)
        try payload.write(to: urls.payloadURL, options: .atomic)
    }

    /// Ensures the cache directory exists before any IO.
    private func ensureDirectoryExists() throws {
        if didEnsureDirectory {
            return
        }
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        didEnsureDirectory = true
    }

    /// Returns filenames derived from the query key.
    private func cacheURLs(for queryKey: String) throws -> (metadataURL: URL, payloadURL: URL, legacyTextURL: URL) {
        let fileName = sanitizedFileName(for: queryKey)
        let metadataURL = directory.appendingPathComponent("\(fileName).json")
        let payloadURL = directory.appendingPathComponent("\(fileName).dat")
        let legacyTextURL = directory.appendingPathComponent("\(fileName).tle")
        return (metadataURL, payloadURL, legacyTextURL)
    }

    /// Keeps filenames safe for the filesystem by replacing unsafe characters.
    private func sanitizedFileName(for queryKey: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = queryKey.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "_"
        }
        let result = String(mapped)
        return result.isEmpty ? "default" : result
    }

    /// Reads the payload data, migrating legacy .tle files to the new .dat format.
    private func loadPayloadData(urls: (metadataURL: URL, payloadURL: URL, legacyTextURL: URL)) throws -> Data {
        if fileManager.fileExists(atPath: urls.payloadURL.path) {
            return try Data(contentsOf: urls.payloadURL)
        }

        guard fileManager.fileExists(atPath: urls.legacyTextURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let legacyData = try Data(contentsOf: urls.legacyTextURL)
        // Migrate legacy text payloads to the new data-backed format for future loads.
        try legacyData.write(to: urls.payloadURL, options: .atomic)
        try? fileManager.removeItem(at: urls.legacyTextURL)
        return legacyData
    }

    /// Decodes UTF-8 text payloads when the content type indicates text.
    nonisolated func decodeTextPayload(_ record: TLECacheRecord) -> String? {
        guard record.metadata.contentType.hasPrefix("text/") else { return nil }
        return String(data: record.payload, encoding: .utf8)
    }
}
