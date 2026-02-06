//
//  TrackingViewModelTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Unit tests for the tracking loop start/stop behavior.
struct TrackingViewModelTests {

    /// Manual ticker that lets tests emit deterministic ticks.
    private actor ManualTicker: TrackingTicker {
        private let stream: AsyncStream<Date>
        private let continuation: AsyncStream<Date>.Continuation

        init() {
            var captured: AsyncStream<Date>.Continuation!
            stream = AsyncStream { continuation in
                captured = continuation
            }
            continuation = captured
        }

        nonisolated func ticks() -> AsyncStream<Date> {
            stream
        }

        func send(_ date: Date) {
            continuation.yield(date)
        }

        func finish() {
            continuation.finish()
        }
    }

    /// Service stub for providing a known TLE payload.
    private actor MockService: CelesTrakTLEService {
        private let response: TLEFetchResult

        init(response: TLEFetchResult) {
            self.response = response
        }

        func fetchTLEText(nameQuery: String, cacheMetadata: TLECacheMetadata?) async throws -> TLEFetchResult {
            response
        }

        func fetchTLEs(nameQuery: String) async throws -> [TLE] {
            let payload: Data
            let contentType: String
            switch response {
            case .payload(let result):
                payload = await MainActor.run { result.payload }
                contentType = await MainActor.run { result.contentType }
            case .notModified:
                throw CelesTrakError.notModified
            }

            if contentType.hasPrefix("application/json") {
                return try CelesTrakTLEClient.decodeJSONPayload(payload)
            }

            let text = String(decoding: payload, as: UTF8.self)
            return try CelesTrakTLEClient.parseTLEText(text)
        }

        nonisolated static func parseTLEText(_ text: String) throws -> [TLE] {
            try CelesTrakTLEClient.parseTLEText(text)
        }
    }

    /// Service stub that always throws a specific error.
    private actor ErrorService: CelesTrakTLEService {
        private let thrownError: Error

        init(thrownError: Error) {
            self.thrownError = thrownError
        }

        func fetchTLEText(nameQuery: String, cacheMetadata: TLECacheMetadata?) async throws -> TLEFetchResult {
            throw thrownError
        }

        func fetchTLEs(nameQuery: String) async throws -> [TLE] {
            throw thrownError
        }

        nonisolated static func parseTLEText(_ text: String) throws -> [TLE] {
            try CelesTrakTLEClient.parseTLEText(text)
        }
    }

    /// Orbit engine stub that always fails propagation.
    private struct AlwaysFailOrbitEngine: OrbitEngine {
        private struct OrbitFailure: Error {}

        func position(for satellite: Satellite, at date: Date) throws -> SatellitePosition {
            throw OrbitFailure()
        }
    }

    /// Helper error used to verify unexpected error messaging.
    private enum UnexpectedFailure: Error {
        case failed
    }

    /// Generates a small, valid 3-line TLE block for tests.
    private func makeText(name: String) -> String {
        """
        \(name)
        1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991
        2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456
        """
    }

    /// Creates a repository configured to return a single payload.
    private func makeRepository(withText text: String) async throws -> TLERepository {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let response = TLEFetchResponse(
            payload: Data(text.utf8),
            contentType: "text/tle",
            sourceURL: URL(string: "https://example.com/tle")!,
            etag: nil,
            lastModified: nil
        )
        let service = MockService(response: .payload(response))

        return TLERepository(
            service: service,
            cacheStore: TLECacheStore(directory: cacheDirectory)
        )
    }

    /// Waits briefly for the view model to publish an update.
    @MainActor
    private func waitForUpdate(matching date: Date, in viewModel: TrackingViewModel) async -> Bool {
        for _ in 0..<50 {
            if viewModel.lastUpdatedAt == date {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    /// Waits for the view model to publish an error string.
    @MainActor
    private func waitForError(in viewModel: TrackingViewModel) async -> String? {
        for _ in 0..<50 {
            if let message = viewModel.state.error {
                return message
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }

    /// Creates a repository that always throws from the remote service.
    private func makeFailingRepository(error: Error) async throws -> TLERepository {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        return TLERepository(
            service: ErrorService(thrownError: error),
            cacheStore: TLECacheStore(directory: cacheDirectory)
        )
    }

    /// Ensures startTracking begins producing updates from ticks.
    @Test @MainActor func startTracking_producesUpdates() async throws {
        let ticker = ManualTicker()
        let repository = try await makeRepository(withText: makeText(name: "ALPHA"))
        let viewModel = TrackingViewModel(
            repository: repository,
            orbitEngine: StubOrbitEngine(),
            ticker: ticker
        )

        viewModel.startTracking(queryKey: "SPACEMOBILE")
        let tick = Date(timeIntervalSince1970: 1_000)
        await ticker.send(tick)

        let didUpdate = await waitForUpdate(matching: tick, in: viewModel)
        #expect(didUpdate)
        #expect(!viewModel.trackedSatellites.isEmpty)
    }

    /// Ensures stopTracking cancels the loop and stops further updates.
    @Test @MainActor func stopTracking_stopsUpdates() async throws {
        let ticker = ManualTicker()
        let repository = try await makeRepository(withText: makeText(name: "BETA"))
        let viewModel = TrackingViewModel(
            repository: repository,
            orbitEngine: StubOrbitEngine(),
            ticker: ticker
        )

        viewModel.startTracking(queryKey: "SPACEMOBILE")
        let firstTick = Date(timeIntervalSince1970: 2_000)
        await ticker.send(firstTick)
        _ = await waitForUpdate(matching: firstTick, in: viewModel)

        viewModel.stopTracking()

        let secondTick = Date(timeIntervalSince1970: 2_001)
        await ticker.send(secondTick)
        try? await Task.sleep(nanoseconds: 30_000_000)

        #expect(viewModel.lastUpdatedAt == firstTick)
    }

    /// Ensures each tick updates the tracked positions.
    @Test @MainActor func tracking_updatesOnEachTick() async throws {
        let ticker = ManualTicker()
        let repository = try await makeRepository(withText: makeText(name: "GAMMA"))
        let viewModel = TrackingViewModel(
            repository: repository,
            orbitEngine: StubOrbitEngine(),
            ticker: ticker
        )

        viewModel.startTracking(queryKey: "SPACEMOBILE")

        let firstTick = Date(timeIntervalSince1970: 3_000)
        await ticker.send(firstTick)
        _ = await waitForUpdate(matching: firstTick, in: viewModel)
        let firstPosition = viewModel.trackedSatellites.first?.position

        let secondTick = Date(timeIntervalSince1970: 3_001)
        await ticker.send(secondTick)
        let didUpdate = await waitForUpdate(matching: secondTick, in: viewModel)

        let secondPosition = viewModel.trackedSatellites.first?.position

        #expect(didUpdate)
        #expect(secondPosition?.timestamp == secondTick)
        #expect(firstPosition != secondPosition)
    }

    /// Ensures typed repository errors are surfaced with a user-friendly message.
    @Test @MainActor func startTracking_onTypedRepositoryError_setsErrorState() async throws {
        let ticker = ManualTicker()
        let repository = try await makeFailingRepository(error: CelesTrakError.badStatus(503))
        let viewModel = TrackingViewModel(
            repository: repository,
            orbitEngine: StubOrbitEngine(),
            ticker: ticker
        )

        viewModel.startTracking(queryKey: "SPACEMOBILE")

        let message = await waitForError(in: viewModel)
        #expect(message?.contains("503") == true)
        #expect(viewModel.trackedSatellites.isEmpty)
        #expect(viewModel.lastUpdatedAt == nil)
        #expect(viewModel.lastTLEFetchedAt == nil)
    }

    /// Ensures unexpected failures use the generic fallback error message.
    @Test @MainActor func startTracking_onUnexpectedError_usesFallbackMessage() async throws {
        let ticker = ManualTicker()
        let repository = try await makeFailingRepository(error: UnexpectedFailure.failed)
        let viewModel = TrackingViewModel(
            repository: repository,
            orbitEngine: StubOrbitEngine(),
            ticker: ticker
        )

        viewModel.startTracking(queryKey: "SPACEMOBILE")

        let message = await waitForError(in: viewModel)
        #expect(message?.contains("unexpected error occurred") == true)
    }

    /// Ensures orbit-propagation failures skip satellites instead of crashing the loop.
    @Test @MainActor func tracking_withOrbitFailures_stillPublishesEmptyLoadedState() async throws {
        let ticker = ManualTicker()
        let repository = try await makeRepository(withText: makeText(name: "DELTA"))
        let viewModel = TrackingViewModel(
            repository: repository,
            orbitEngine: AlwaysFailOrbitEngine(),
            ticker: ticker
        )

        viewModel.startTracking(queryKey: "SPACEMOBILE")
        let tick = Date(timeIntervalSince1970: 4_000)
        await ticker.send(tick)

        let didUpdate = await waitForUpdate(matching: tick, in: viewModel)
        #expect(didUpdate)
        #expect(viewModel.trackedSatellites.isEmpty)
        #expect(viewModel.state.data?.isEmpty == true)
    }
}
