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
        var delayNanoseconds: UInt64 = 0

        func fetchTLEText(nameQuery: String, cacheMetadata: TLECacheMetadata?) async throws -> TLEFetchResult {
            callCount += 1
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
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

        func setDelayNanoseconds(_ value: UInt64) {
            delayNanoseconds = value
        }
    }

    /// Mutable clock helper so tests can move "current time" forward.
    ///
    /// The repository's `clock` dependency is synchronous, so this helper uses
    /// an explicit lock to provide thread-safe reads and writes across tasks.
    private final class MutableClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date

        init(_ value: Date) {
            self.value = value
        }

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ value: Date) {
            lock.lock()
            self.value = value
            lock.unlock()
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

    /// Forces refresh to hit the network even when cache is still fresh.
    @Test @MainActor func refresh_alwaysUsesNetworkWhenAvailable() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)

        try await cacheStore.save(
            queryKey: "SPACEMOBILE",
            payload: Data(makeText(name: "FRESH-CACHE").utf8),
            sourceURL: URL(string: "https://example.com/cache")!,
            fetchedAt: now.addingTimeInterval(-60),
            contentType: "text/tle"
        )

        let service = MockService()
        await service.setResponse(
            .payload(
                TLEFetchResponse(
                    payload: Data(makeText(name: "REFRESHED").utf8),
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

        let result = try await repository.refreshTLEs(queryKey: "SPACEMOBILE")
        #expect(await service.getCallCount() == 1)
        #expect(result.source == .network)
        #expect(result.tles.first?.name == "REFRESHED")
    }

    /// Keeps the app functional when manual refresh fails but cache exists.
    @Test @MainActor func refresh_fallsBackToCacheWhenNetworkFails() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)

        try await cacheStore.save(
            queryKey: "SPACEMOBILE",
            payload: Data(makeText(name: "SAFE-CACHE").utf8),
            sourceURL: URL(string: "https://example.com/cache")!,
            fetchedAt: now.addingTimeInterval(-120),
            contentType: "text/tle"
        )

        let service = MockService()
        await service.setError(MockError.failed)

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            clock: { now }
        )

        let result = try await repository.refreshTLEs(queryKey: "SPACEMOBILE")
        #expect(await service.getCallCount() == 1)
        #expect(result.source == .cache)
        #expect(result.tles.first?.name == "SAFE-CACHE")
    }

    /// Applies per-query 403 backoff and avoids repeated blocked calls.
    @Test @MainActor func getTLEs_on403WithCache_secondCallUsesBackoffWithoutNetwork() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let cacheStore = TLECacheStore(directory: cacheDirectory)
        let policy = TLECachePolicy(staleAfter: 60)

        try await cacheStore.save(
            queryKey: "SPACEMOBILE",
            payload: Data(makeText(name: "CACHED").utf8),
            sourceURL: URL(string: "https://example.com/cache")!,
            fetchedAt: now.addingTimeInterval(-120),
            contentType: "text/tle"
        )

        let service = MockService()
        await service.setError(CelesTrakError.badStatus(403))

        let repository = TLERepository(
            service: service,
            cacheStore: cacheStore,
            policy: policy,
            clock: { now }
        )

        let first = try await repository.getTLEs(queryKey: "SPACEMOBILE")
        let second = try await repository.getTLEs(queryKey: "SPACEMOBILE")

        #expect(await service.getCallCount() == 1)
        #expect(first.source == .cache)
        #expect(second.source == .cache)
        #expect(first.tles.first?.name == "CACHED")
        #expect(second.tles.first?.name == "CACHED")
    }

    /// Applies 403 backoff even when no cache exists, preventing rapid retries.
    @Test @MainActor func getTLEs_on403WithoutCache_secondCallFailsWithoutSecondNetworkAttempt() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let service = MockService()
        await service.setError(CelesTrakError.badStatus(403))

        let repository = TLERepository(
            service: service,
            cacheStore: TLECacheStore(directory: cacheDirectory),
            clock: { now }
        )

        do {
            _ = try await repository.getTLEs(queryKey: "SPACEMOBILE")
            Issue.record("Expected initial 403 to throw")
        } catch let error as CelesTrakError {
            guard case .badStatus(403) = error else {
                Issue.record("Expected .badStatus(403), got \(error)")
                return
            }
        }

        do {
            _ = try await repository.getTLEs(queryKey: "SPACEMOBILE")
            Issue.record("Expected backoff to keep throwing 403")
        } catch let error as CelesTrakError {
            guard case .badStatus(403) = error else {
                Issue.record("Expected .badStatus(403), got \(error)")
                return
            }
        }

        #expect(await service.getCallCount() == 1)
    }

    /// Allows retries again after the two-hour backoff window expires.
    @Test @MainActor func getTLEs_afterBackoffExpiry_retriesNetworkAndSucceeds() async throws {
        let initial = Date(timeIntervalSince1970: 1_000_000)
        let mutableClock = MutableClock(initial)
        let cacheDirectory = try makeTempDirectory()
        let service = MockService()
        await service.setError(CelesTrakError.badStatus(403))

        let repository = TLERepository(
            service: service,
            cacheStore: TLECacheStore(directory: cacheDirectory),
            clock: { mutableClock.now() }
        )

        do {
            _ = try await repository.getTLEs(queryKey: "SPACEMOBILE")
            Issue.record("Expected initial 403 to throw")
        } catch let error as CelesTrakError {
            guard case .badStatus(403) = error else {
                Issue.record("Expected .badStatus(403), got \(error)")
                return
            }
        }

        mutableClock.set(initial.addingTimeInterval(2 * 60 * 60 + 1))
        await service.setError(nil)
        await service.setResponse(
            .payload(
                TLEFetchResponse(
                    payload: Data(makeText(name: "RECOVERED").utf8),
                    contentType: "text/tle",
                    sourceURL: URL(string: "https://example.com/remote")!,
                    etag: nil,
                    lastModified: nil
                )
            )
        )

        let result = try await repository.getTLEs(queryKey: "SPACEMOBILE")

        #expect(await service.getCallCount() == 2)
        #expect(result.source == .network)
        #expect(result.tles.first?.name == "RECOVERED")
    }

    /// Shares one in-flight request across concurrent callers for the same key.
    @Test @MainActor func getTLEs_concurrentCallers_shareInFlightTask() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheDirectory = try makeTempDirectory()
        let service = MockService()
        await service.setDelayNanoseconds(200_000_000)
        await service.setResponse(
            .payload(
                TLEFetchResponse(
                    payload: Data(makeText(name: "IN-FLIGHT").utf8),
                    contentType: "text/tle",
                    sourceURL: URL(string: "https://example.com/remote")!,
                    etag: nil,
                    lastModified: nil
                )
            )
        )

        let repository = TLERepository(
            service: service,
            cacheStore: TLECacheStore(directory: cacheDirectory),
            clock: { now }
        )

        async let first = repository.getTLEs(queryKey: "SPACEMOBILE")
        async let second = repository.getTLEs(queryKey: "SPACEMOBILE")
        let results = try await [first, second]

        #expect(await service.getCallCount() == 1)
        #expect(results[0].tles.first?.name == "IN-FLIGHT")
        #expect(results[1].tles.first?.name == "IN-FLIGHT")
        #expect(results[0].source == .network)
        #expect(results[1].source == .network)
    }
}
