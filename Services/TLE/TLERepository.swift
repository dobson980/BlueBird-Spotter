//
//  TLERepository.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation

/// Combined result that includes parsed TLEs and the source of truth.
struct TLERepositoryResult: Sendable, Equatable {
    /// Indicates where the returned data was sourced from.
    enum Source: Sendable, Equatable {
        /// Data parsed from the local cache.
        case cache
        /// Data fetched from the network and then cached.
        case network
    }

    let tles: [TLE]
    let fetchedAt: Date
    let source: Source
}

/// Coordinates cache reads, conditional refresh, and fallback behavior.
actor TLERepository {
    /// Shared repository instance to avoid duplicate fetches across views.
    @MainActor static let shared = TLERepository.makeDefault()

    private let service: any CelesTrakTLEService
    private let cacheStore: TLECacheStore
    private let policy: TLECachePolicy
    private let clock: @Sendable () -> Date
    /// Tracks in-flight requests so multiple callers share one network fetch.
    private var inFlight: [String: Task<TLERepositoryResult, Error>] = [:]
    /// Backoff window for servers that block frequent requests (per query key).
    private var blockedUntil: [String: Date] = [:]

    /// Designated initializer for tests and alternate dependencies.
    init(
        service: any CelesTrakTLEService,
        cacheStore: TLECacheStore,
        policy: TLECachePolicy = TLECachePolicy(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.cacheStore = cacheStore
        self.policy = policy
        self.clock = clock
    }

    /// Convenience factory for production defaults.
    @MainActor
    static func makeDefault() -> TLERepository {
        TLERepository(
            service: CelesTrakTLEClient(),
            cacheStore: TLECacheStore(),
            policy: TLECachePolicy(),
            clock: Date.init
        )
    }

    /// Returns cached data immediately when fresh, otherwise refreshes.
    func getTLEs(queryKey: String) async throws -> TLERepositoryResult {
        if let existing = inFlight[queryKey] {
            return try await existing.value
        }

        let task = Task { [weak self] in
            guard let self else { throw CelesTrakError.emptyBody }
            return try await self.fetchTLEsInternal(queryKey: queryKey)
        }
        inFlight[queryKey] = task

        do {
            let result = try await task.value
            inFlight[queryKey] = nil
            return result
        } catch {
            inFlight[queryKey] = nil
            throw error
        }
    }

    /// Forces a network refresh and falls back to cache if available.
    func refreshTLEs(queryKey: String) async throws -> TLERepositoryResult {
        let cached = try await loadCached(queryKey: queryKey)
        do {
            return try await fetchFromNetwork(queryKey: queryKey, cachedRecord: cached?.record)
        } catch {
            if let cached {
                return cached.result
            }
            throw error
        }
    }

    /// Performs the cache-first lookup and conditional refresh flow.
    private func fetchTLEsInternal(queryKey: String) async throws -> TLERepositoryResult {
        // Step A: try cache first so the UI can render without waiting.
        if let cached = try await loadCached(queryKey: queryKey) {
            if !policy.isStale(fetchedAt: cached.result.fetchedAt, now: clock()) {
                return cached.result
            }

            // Step B: stale cache triggers a refresh, but we can fall back.
            do {
                return try await fetchFromNetwork(queryKey: queryKey, cachedRecord: cached.record)
            } catch {
                return cached.result
            }
        }

        return try await fetchFromNetwork(queryKey: queryKey, cachedRecord: nil)
    }

    /// Attempts to load cached data and parse it into TLEs.
    private func loadCached(queryKey: String) async throws -> (result: TLERepositoryResult, record: TLECacheRecord)? {
        guard let record = try await cacheStore.load(queryKey: queryKey) else { return nil }
        guard let tles = try? decodeAndFilter(record: record) else { return nil }
        let result = TLERepositoryResult(
            tles: tles,
            fetchedAt: record.metadata.fetchedAt,
            source: .cache
        )
        return (result: result, record: record)
    }

    /// Fetches raw text from the network, caches it, and returns parsed TLEs.
    private func fetchFromNetwork(queryKey: String, cachedRecord: TLECacheRecord?) async throws -> TLERepositoryResult {
        let now = clock()
        if let blocked = blockedUntil[queryKey], now < blocked {
            if let cachedRecord {
                let tles = try decodeAndFilter(record: cachedRecord)
                return TLERepositoryResult(tles: tles, fetchedAt: cachedRecord.metadata.fetchedAt, source: .cache)
            }
            throw CelesTrakError.badStatus(403)
        } else if let blocked = blockedUntil[queryKey], now >= blocked {
            blockedUntil[queryKey] = nil
        }

        let result = try await fetchWithBackoff(queryKey: queryKey, cachedRecord: cachedRecord)
        let fetchedAt = clock()

        switch result {
        case .payload(let response):
            // Save raw payload so future loads can parse without a network request.
            try await cacheStore.save(
                queryKey: queryKey,
                payload: response.payload,
                sourceURL: response.sourceURL,
                fetchedAt: fetchedAt,
                contentType: response.contentType,
                etag: response.etag,
                lastModified: response.lastModified
            )
            let tles = try decodeAndFilter(payload: response.payload, contentType: response.contentType)
            return TLERepositoryResult(tles: tles, fetchedAt: fetchedAt, source: .network)
        case .notModified(let etag, let lastModified, let sourceURL):
            guard let cachedRecord else { throw CelesTrakError.notModified }
            try await cacheStore.save(
                queryKey: queryKey,
                payload: cachedRecord.payload,
                sourceURL: sourceURL,
                fetchedAt: fetchedAt,
                contentType: cachedRecord.metadata.contentType,
                etag: etag ?? cachedRecord.metadata.etag,
                lastModified: lastModified ?? cachedRecord.metadata.lastModified
            )
            let tles = try decodeAndFilter(record: cachedRecord)
            return TLERepositoryResult(tles: tles, fetchedAt: fetchedAt, source: .cache)
        }
    }

    /// Wraps network fetches to enforce backoff on 403 responses.
    private func fetchWithBackoff(queryKey: String, cachedRecord: TLECacheRecord?) async throws -> TLEFetchResult {
        do {
            return try await service.fetchTLEText(nameQuery: queryKey, cacheMetadata: cachedRecord?.metadata)
        } catch let error as CelesTrakError {
            if case .badStatus(403) = error {
                blockedUntil[queryKey] = clock().addingTimeInterval(2 * 60 * 60)
            }
            throw error
        }
    }

    /// Parses cached payloads based on content type before filtering.
    private func decodeAndFilter(record: TLECacheRecord) throws -> [TLE] {
        try decodeAndFilter(payload: record.payload, contentType: record.metadata.contentType)
    }

    /// Parses payloads into TLEs and applies filtering rules.
    private func decodeAndFilter(payload: Data, contentType: String) throws -> [TLE] {
        let parsed: [TLE]
        if contentType.hasPrefix("application/json") {
            parsed = try CelesTrakTLEClient.decodeJSONPayload(payload)
        } else {
            let text = String(decoding: payload, as: UTF8.self)
            parsed = try CelesTrakTLEClient.parseTLEText(text)
        }
        return TLEFilter.excludeDebris(from: parsed)
    }
}
