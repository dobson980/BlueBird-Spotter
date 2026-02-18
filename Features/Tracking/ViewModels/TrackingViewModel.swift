//
//  TrackingViewModel.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import Observation

/// Tracks satellites at 1Hz using a repository, ticker, and orbit engine.
///
/// The view model keeps heavy propagation work off the main thread, while
/// publishing UI-friendly state updates on the main actor.
@MainActor
@Observable
final class TrackingViewModel {
    /// Repository that loads TLEs for the tracking session.
    private let repository: TLERepository
    /// Orbit engine used to compute geodetic positions from TLEs.
    private let orbitEngine: any OrbitEngine
    /// Tick source that drives the 1Hz update loop.
    private let ticker: TrackingTicker
    /// Background task that runs the tracking loop.
    private var trackingTask: Task<Void, Never>?

    /// Latest tracked positions for display.
    var trackedSatellites: [TrackedSatellite] = []
    /// UI-friendly load state for tracking updates.
    var state: LoadState<[TrackedSatellite]> = .idle
    /// Timestamp of the most recent update.
    var lastUpdatedAt: Date?
    /// Timestamp of the most recent TLE fetch that seeded tracking.
    var lastTLEFetchedAt: Date?

    /// Designated initializer that supports dependency injection for tests.
    init(
        repository: TLERepository = TLERepository.shared,
        orbitEngine: any OrbitEngine = SGP4OrbitEngine(),
        ticker: TrackingTicker = RealTimeTicker()
    ) {
        self.repository = repository
        self.orbitEngine = orbitEngine
        self.ticker = ticker
    }

    /// Starts loading TLEs and begins the 1Hz tracking loop.
    func startTracking(queryKey: String) {
        startTracking(queryKeys: [queryKey])
    }

    /// Starts loading multiple TLE query groups and begins the 1Hz tracking loop.
    func startTracking(queryKeys: [String]) {
        stopTracking()
        state = .loading
        let normalizedQueryKeys = Self.normalizedQueryKeys(from: queryKeys)
        guard !normalizedQueryKeys.isEmpty else {
            state = .error("No tracking query keys are configured.")
            return
        }

        trackingTask = Task.detached { [weak self, repository, orbitEngine, ticker] in
            guard let self else { return }

            do {
                var fetchedAtDates: [Date] = []
                var combinedTLEs: [TLE] = []
                for queryKey in normalizedQueryKeys {
                    let result = try await repository.getTLEs(queryKey: queryKey)
                    combinedTLEs.append(contentsOf: result.tles)
                    fetchedAtDates.append(result.fetchedAt)
                }
                let mergedTLEs = Self.deduplicatedTLEs(combinedTLEs)
                let satellites = mergedTLEs.map { Self.makeSatellite(from: $0) }
                let latestFetchedAt = fetchedAtDates.max()

                await MainActor.run {
                    self.trackedSatellites = []
                    self.lastUpdatedAt = nil
                    self.lastTLEFetchedAt = latestFetchedAt
                }

                for await tick in ticker.ticks() {
                    guard !Task.isCancelled else { break }

                    var tracked: [TrackedSatellite] = []
                    tracked.reserveCapacity(satellites.count)
                    for satellite in satellites {
                        guard let position = try? orbitEngine.position(for: satellite, at: tick) else {
                            continue
                        }
                        tracked.append(TrackedSatellite(satellite: satellite, position: position))
                    }

                    await MainActor.run {
                        self.trackedSatellites = tracked
                        self.lastUpdatedAt = tick
                        self.state = .loaded(tracked)
                    }
                }
            } catch let error as CelesTrakError {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                    self.trackedSatellites = []
                    self.lastUpdatedAt = nil
                    self.lastTLEFetchedAt = nil
                }
            } catch {
                await MainActor.run {
                    self.state = .error("An unexpected error occurred: \(error)")
                    self.trackedSatellites = []
                    self.lastUpdatedAt = nil
                    self.lastTLEFetchedAt = nil
                }
            }
        }
    }

    /// Stops the tracking loop and cancels any in-flight work.
    func stopTracking() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    /// Builds a `Satellite` model from a TLE entry, parsing the NORAD id when possible.
    nonisolated private static func makeSatellite(from tle: TLE) -> Satellite {
        let name = tle.name ?? "Unknown"
        let id = parseNoradID(from: tle.line1) ?? fallbackIdentifier(for: name, line1: tle.line1, line2: tle.line2)

        return Satellite(
            id: id,
            name: name,
            tleLine1: tle.line1,
            tleLine2: tle.line2,
            epoch: nil
        )
    }

    /// Extracts the NORAD catalog number from a TLE line if the format is valid.
    nonisolated private static func parseNoradID(from line1: String) -> Int? {
        guard line1.count >= 7 else { return nil }
        let start = line1.index(line1.startIndex, offsetBy: 2)
        let end = line1.index(start, offsetBy: 5)
        let idString = line1[start..<end].trimmingCharacters(in: .whitespaces)
        return Int(idString)
    }

    /// Generates a deterministic fallback id for TLEs without a parsable catalog number.
    nonisolated private static func fallbackIdentifier(for name: String, line1: String, line2: String) -> Int {
        let input = "\(name)|\(line1)|\(line2)"
        var hash: UInt64 = 1469598103934665603
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let value = Int(hash % UInt64(Int.max - 1)) + 1
        return value
    }

    /// Keeps only unique query keys while preserving user-intended order.
    nonisolated private static func normalizedQueryKeys(from queryKeys: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for query in queryKeys {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let uppercased = trimmed.uppercased()
            if seen.insert(uppercased).inserted {
                normalized.append(trimmed)
            }
        }
        return normalized
    }

    /// Removes duplicate TLE entries when multiple query buckets overlap.
    nonisolated private static func deduplicatedTLEs(_ tles: [TLE]) -> [TLE] {
        var seenNoradIDs = Set<Int>()
        var seenFallbackKeys = Set<String>()
        var deduplicated: [TLE] = []
        deduplicated.reserveCapacity(tles.count)

        for tle in tles {
            if let noradID = parseNoradID(from: tle.line1) {
                guard seenNoradIDs.insert(noradID).inserted else { continue }
                deduplicated.append(tle)
                continue
            }

            let fallbackKey = "\(tle.line1)|\(tle.line2)"
            guard seenFallbackKeys.insert(fallbackKey).inserted else { continue }
            deduplicated.append(tle)
        }
        return deduplicated
    }
}
