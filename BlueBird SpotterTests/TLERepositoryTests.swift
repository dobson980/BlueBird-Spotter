//
//  TLERepositoryTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Unit tests for cache freshness and fallback behavior in the repository.
struct TLERepositoryTests {

    private enum MockError: Error {
        case failed
    }

    /// Minimal service stub for controlling success and failure paths.
    private actor MockService: CelesTrakTLEService {
        private(set) var callCount = 0
        var response: TLEFetchResult?
        var error: Error?

        func fetchTLEText(nameQuery: String, cacheMetadata: TLECacheMetadata?) async throws -> TLEFetchResult {
            callCount += 1
            if let error {
                throw error
            }
            return response!
        }

        func fetchTLEs(nameQuery: String) async throws -> [TLE] {
            let result = try await fetchTLEText(nameQuery: nameQuery, cacheMetadata: nil)
            guard case let .payload(response) = result else {
                throw CelesTrakError.notModified
            }
            // Use a main-actor hop to access default-isolated response values in tests.
            let payload = await MainActor.run { response.payload }
            let contentType = await MainActor.run { response.contentType }
            let parsed: [TLE]
            if contentType.hasPrefix("application/json") {
                parsed = try CelesTrakTLEClient.decodeJSONPayload(payload)
            } else {
                let text = String(decoding: payload, as: UTF8.self)
                parsed = try Self.parseTLEText(text)
            }
            return TLEFilter.excludeDebris(from: parsed)
        }

        nonisolated static func parseTLEText(_ text: String) throws -> [TLE] {
            try CelesTrakTLEClient.parseTLEText(text)
        }

        func getCallCount() -> Int {
            callCount
        }

        func setResponse(_ response: TLEFetchResult?) {
            self.response = response
        }

        func setError(_ error: Error?) {
            self.error = error
        }
    }

    /// Creates a unique temp directory for isolated cache files.
    private func makeTempDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generates a small, valid 3-line TLE block for tests.
    private func makeText(name: String) -> String {
        """
        \(name)
        1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        """
    }

    /// Uses cache when data is fresh and avoids a network call.
    @Test @MainActor func repository_usesFreshCacheWithoutNetwork() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let text = makeText(name: "ALPHA")
        let sourceURL = URL(string: "https://example.com/cache")!

        try await cacheStore.save(
            queryKey: "SPACEMOBILE",
            payload: Data(text.utf8),
            sourceURL: sourceURL,
            fetchedAt: now.addingTimeInterval(-3600),
            contentType: "text/tle"
        )

        let service = MockService()
        await service.setResponse(
            .payload(
                TLEFetchResponse(
                    payload: Data(makeText(name: "REMOTE").utf8),
                    contentType: "text/tle",
                    sourceURL: URL(string: "https://example.com/remote")!,
                    etag: nil,
                    lastModified: nil
                )
            )
        )

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        let result = try await repository.getTLEs(queryKey: "SPACEMOBILE")

        #expect(await service.getCallCount() == 0)
        #expect(result.tles.first?.name == "ALPHA")
        #expect(result.source == .cache)
    }

    /// Refreshes from the network when cache is stale.
    @Test @MainActor func repository_refreshesWhenCacheIsStale() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let sourceURL = URL(string: "https://example.com/cache")!

        try await cacheStore.save(
            queryKey: "SPACEMOBILE",
            payload: Data(makeText(name: "OLD").utf8),
            sourceURL: sourceURL,
            fetchedAt: now.addingTimeInterval(-7 * 60 * 60),
            contentType: "text/tle"
        )

        let service = MockService()
        await service.setResponse(
            .payload(
                TLEFetchResponse(
                    payload: Data(makeText(name: "NEW").utf8),
                    contentType: "text/tle",
                    sourceURL: URL(string: "https://example.com/remote")!,
                    etag: nil,
                    lastModified: nil
                )
            )
        )

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        let result = try await repository.getTLEs(queryKey: "SPACEMOBILE")
        let cachedRecord = try await cacheStore.load(queryKey: "SPACEMOBILE")

        #expect(await service.getCallCount() == 1)
        #expect(result.tles.first?.name == "NEW")
        #expect(result.source == .network)
        #expect(cachedRecord?.metadata.fetchedAt == now)
    }

    /// Falls back to cached data if the refresh fails.
    @Test @MainActor func repository_fallsBackToCacheOnNetworkFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let sourceURL = URL(string: "https://example.com/cache")!

        try await cacheStore.save(
            queryKey: "SPACEMOBILE",
            payload: Data(makeText(name: "CACHED").utf8),
            sourceURL: sourceURL,
            fetchedAt: now.addingTimeInterval(-7 * 60 * 60),
            contentType: "text/tle"
        )

        let service = MockService()
        await service.setError(MockError.failed)

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        let result = try await repository.getTLEs(queryKey: "SPACEMOBILE")

        #expect(await service.getCallCount() == 1)
        #expect(result.tles.first?.name == "CACHED")
        #expect(result.source == .cache)
    }

    /// Saves and returns data when no cache exists but the network succeeds.
    @Test @MainActor func repository_fetchesWhenCacheMissing() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let service = MockService()
        await service.setResponse(
            .payload(
                TLEFetchResponse(
                    payload: Data(makeText(name: "NEW").utf8),
                    contentType: "text/tle",
                    sourceURL: URL(string: "https://example.com/remote")!,
                    etag: nil,
                    lastModified: nil
                )
            )
        )

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        let result = try await repository.getTLEs(queryKey: "SPACEMOBILE")
        let cachedRecord = try await cacheStore.load(queryKey: "SPACEMOBILE")

        #expect(await service.getCallCount() == 1)
        #expect(result.tles.first?.name == "NEW")
        #expect(result.source == .network)
        #expect(cachedRecord?.metadata.fetchedAt == now)
    }

    /// Throws when both network and cache are unavailable.
    @Test @MainActor func repository_throwsWhenNoCacheAndNetworkFails() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let service = MockService()
        await service.setError(MockError.failed)

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        do {
            _ = try await repository.getTLEs(queryKey: "SPACEMOBILE")
            #expect(Bool(false))
        } catch {
            #expect(error is MockError)
        }
    }

    /// Persists ETag and Last-Modified when the network returns fresh data.
    @Test @MainActor func repository_savesValidatorsFromNetwork() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let service = MockService()
        await service.setResponse(
            .payload(
                TLEFetchResponse(
                    payload: Data(makeText(name: "VALIDATORS").utf8),
                    contentType: "text/tle",
                    sourceURL: URL(string: "https://example.com/remote")!,
                    etag: "\"abc123\"",
                    lastModified: "Wed, 01 Jan 2025 00:00:00 GMT"
                )
            )
        )

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        _ = try await repository.getTLEs(queryKey: "SPACEMOBILE")
        let cachedRecord = try await cacheStore.load(queryKey: "SPACEMOBILE")

        #expect(cachedRecord?.metadata.etag == "\"abc123\"")
        #expect(cachedRecord?.metadata.lastModified == "Wed, 01 Jan 2025 00:00:00 GMT")
    }

    /// Revalidates stale cache on 304 and updates fetchedAt.
    @Test @MainActor func repository_revalidatesOnNotModified() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let sourceURL = URL(string: "https://example.com/cache")!

        try await cacheStore.save(
            queryKey: "SPACEMOBILE",
            payload: Data(makeText(name: "CACHED").utf8),
            sourceURL: sourceURL,
            fetchedAt: now.addingTimeInterval(-7 * 60 * 60),
            contentType: "text/tle",
            etag: "\"old\"",
            lastModified: "Tue, 31 Dec 2024 00:00:00 GMT"
        )

        let service = MockService()
        await service.setResponse(
            .notModified(
                etag: "\"new\"",
                lastModified: "Wed, 01 Jan 2025 00:00:00 GMT",
                sourceURL: sourceURL
            )
        )

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        let result = try await repository.getTLEs(queryKey: "SPACEMOBILE")
        let cachedRecord = try await cacheStore.load(queryKey: "SPACEMOBILE")

        #expect(result.source == .cache)
        #expect(result.fetchedAt == now)
        #expect(cachedRecord?.metadata.fetchedAt == now)
        #expect(cachedRecord?.metadata.etag == "\"new\"")
        #expect(cachedRecord?.metadata.lastModified == "Wed, 01 Jan 2025 00:00:00 GMT")
    }
}
