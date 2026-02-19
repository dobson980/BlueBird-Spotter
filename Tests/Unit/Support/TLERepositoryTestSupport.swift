//
//  TLERepositoryTestSupport.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 2/19/26.
//

import Foundation
@testable import BlueBird_Spotter

/// Shared fixtures and helpers for `TLERepository` unit tests.
///
/// Why this exists:
/// - The test suite has many scenarios that reuse the same service doubles.
/// - Pulling helpers out keeps individual test files focused on assertions.
enum TLERepositoryTestSupport {
    /// Lightweight error used in failure-path tests.
    enum MockError: Error {
        case failed
    }

    /// Minimal service stub for controlling success and failure paths.
    actor MockService: CelesTrakTLEService {
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
    final class MutableClock: @unchecked Sendable {
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
    static func makeTempDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generates a small, valid 3-line TLE block for tests.
    static func makeText(name: String) -> String {
        """
        \(name)
        1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        """
    }
}
