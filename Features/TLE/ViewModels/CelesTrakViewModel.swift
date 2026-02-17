//
//  CelesTrakViewModel.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
import Observation

/// Observable state holder that fetches, sorts, and exposes TLE data.
///
/// This type illustrates SwiftUI-style state management with `@Observable`
/// and a single async loading method.
@MainActor
@Observable
final class CelesTrakViewModel {
    /// Plain-English alert payload shown when manual refresh actions are blocked.
    ///
    /// Keeping this as a small value type makes it easy for SwiftUI views
    /// to present and dismiss notices without pulling in service logic.
    struct RefreshNotice: Equatable {
        /// Short heading displayed by the alert.
        let title: String
        /// Longer explanation that tells the user what happened and why.
        let message: String
    }

    /// Storage strategy for persisting manual refresh cooldown timestamps.
    ///
    /// The app uses this in production so cooldown survives app restarts.
    /// Tests can inject `.disabled` to avoid cross-test shared state.
    struct ManualRefreshCooldownPersistence {
        /// This type stores closure-based behavior so tests and previews can
        /// swap storage strategies without introducing network or disk coupling.
        /// Reads the most recent manual refresh attempt timestamp.
        let loadLastAttempt: () -> Date?
        /// Persists the latest manual refresh attempt timestamp.
        let saveLastAttempt: (Date) -> Void
        /// Clears the persisted timestamp when no cooldown should apply.
        let clearLastAttempt: () -> Void

        /// No-op storage used by tests and previews.
        ///
        /// This is computed (not a stored global constant) to keep strict
        /// concurrency checks simple across different Xcode toolchains.
        static var disabled: ManualRefreshCooldownPersistence {
            ManualRefreshCooldownPersistence(
                loadLastAttempt: { nil },
                saveLastAttempt: { _ in },
                clearLastAttempt: {}
            )
        }

        /// UserDefaults-backed storage used by the production app.
        static func userDefaults(
            _ userDefaults: UserDefaults = .standard,
            key: String = "BlueBirdSpotter.TLE.LastManualRefreshAttempt"
        ) -> ManualRefreshCooldownPersistence {
            ManualRefreshCooldownPersistence(
                loadLastAttempt: {
                    let value = userDefaults.double(forKey: key)
                    guard value > 0 else { return nil }
                    return Date(timeIntervalSince1970: value)
                },
                saveLastAttempt: { date in
                    userDefaults.set(date.timeIntervalSince1970, forKey: key)
                },
                clearLastAttempt: {
                    userDefaults.removeObject(forKey: key)
                }
            )
        }
    }

    /// Injected fetcher to support testing or alternate data sources.
    private let fetchHandler: @Sendable (String) async throws -> TLERepositoryResult
    /// Injected refresh handler for manual refresh requests.
    private let refreshHandler: @Sendable (String) async throws -> TLERepositoryResult
    /// Clock injection for deterministic tests and readable time logic.
    private let now: @Sendable () -> Date
    /// Manual refresh cooldown, in seconds, to protect upstream API limits.
    private let manualRefreshInterval: TimeInterval
    /// Persistence adapter that keeps cooldown state across app restarts.
    private let cooldownPersistence: ManualRefreshCooldownPersistence

    /// Latest fetched list for views that want direct access.
    var tles: [TLE] = []
    /// UI-friendly load state for progress and error messaging.
    var state: LoadState<[TLE]> = .idle
    /// Timestamp from the data source, used for freshness display later.
    var lastFetchedAt: Date?
    /// Age of the data in seconds, computed when a result arrives.
    var dataAge: TimeInterval?
    /// Optional alert payload shown for blocked/failed manual refresh attempts.
    var refreshNotice: RefreshNotice?
    /// Stores the latest manual refresh attempt so cooldown checks are consistent.
    private var lastManualRefreshAttemptAt: Date?

    /// Next moment when manual refresh is allowed again, or `nil` if available now.
    ///
    /// This is derived from the most recent manual refresh attempt, not only
    /// successful requests. That protects the API from rapid repeated taps.
    var nextManualRefreshDate: Date? {
        guard let lastManualRefreshAttemptAt else { return nil }
        let nextAllowedRefreshDate = lastManualRefreshAttemptAt.addingTimeInterval(manualRefreshInterval)
        guard nextAllowedRefreshDate > now() else { return nil }
        return nextAllowedRefreshDate
    }

    /// Default initializer that uses the shared production repository.
    init(
        repository: TLERepository = TLERepository.shared,
        manualRefreshInterval: TimeInterval = 15 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        cooldownPersistence: ManualRefreshCooldownPersistence = .userDefaults()
    ) {
        self.fetchHandler = repository.getTLEs
        self.refreshHandler = repository.refreshTLEs
        self.manualRefreshInterval = manualRefreshInterval
        self.now = now
        self.cooldownPersistence = cooldownPersistence
        restorePersistedManualRefreshAttemptIfNeeded()
    }

    /// Test-friendly initializer that injects a custom fetch closure.
    init(
        fetchHandler: @escaping @Sendable (String) async throws -> TLERepositoryResult,
        manualRefreshInterval: TimeInterval = 15 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        cooldownPersistence: ManualRefreshCooldownPersistence = .disabled
    ) {
        self.fetchHandler = fetchHandler
        self.refreshHandler = fetchHandler
        self.manualRefreshInterval = manualRefreshInterval
        self.now = now
        self.cooldownPersistence = cooldownPersistence
        restorePersistedManualRefreshAttemptIfNeeded()
    }

    /// Test-friendly initializer for separate fetch and refresh behaviors.
    init(
        fetchHandler: @escaping @Sendable (String) async throws -> TLERepositoryResult,
        refreshHandler: @escaping @Sendable (String) async throws -> TLERepositoryResult,
        manualRefreshInterval: TimeInterval = 15 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        cooldownPersistence: ManualRefreshCooldownPersistence = .disabled
    ) {
        self.fetchHandler = fetchHandler
        self.refreshHandler = refreshHandler
        self.manualRefreshInterval = manualRefreshInterval
        self.now = now
        self.cooldownPersistence = cooldownPersistence
        restorePersistedManualRefreshAttemptIfNeeded()
    }

    /// Loads TLEs and updates state for the view layer.
    ///
    /// The method also sorts results alphabetically by satellite name.
    func fetchTLEs(nameQuery: String) async {
        await fetchTLEs(nameQueries: [nameQuery])
    }

    /// Loads multiple TLE query groups and merges results into one list.
    func fetchTLEs(nameQueries: [String]) async {
        refreshNotice = nil
        await loadTLEs(
            using: fetchHandler,
            nameQueries: nameQueries,
            clearsExistingDataOnFailure: true,
            showsRefreshFailureNotice: false
        )
    }

    /// Triggers a foreground refresh that bypasses cache staleness checks.
    func refreshTLEs(nameQuery: String) async {
        await refreshTLEs(nameQueries: [nameQuery])
    }

    /// Triggers a foreground refresh for multiple query groups.
    func refreshTLEs(nameQueries: [String]) async {
        if let nextManualRefreshDate {
            refreshNotice = manualRefreshCooldownNotice(nextAllowedRefreshDate: nextManualRefreshDate)
            return
        }

        refreshNotice = nil
        recordManualRefreshAttempt(at: now())
        await loadTLEs(
            using: refreshHandler,
            nameQueries: nameQueries,
            clearsExistingDataOnFailure: false,
            showsRefreshFailureNotice: true
        )
    }

    /// Clears the currently displayed refresh notice.
    ///
    /// Views call this after the user dismisses the alert.
    func clearRefreshNotice() {
        refreshNotice = nil
    }

    /// Formats a refresh timestamp as short relative text for UI labels.
    ///
    /// Keeping this inside the view model ensures the list header and alert
    /// message use the same formatting rules across the feature.
    func relativeRefreshTimeText(for date: Date) -> String {
        relativeTimeText(for: date)
    }

    /// Shared load path for fetch and refresh actions.
    private func loadTLEs(
        using handler: @escaping @Sendable (String) async throws -> TLERepositoryResult,
        nameQueries: [String],
        clearsExistingDataOnFailure: Bool,
        showsRefreshFailureNotice: Bool
    ) async {
        guard !state.isLoading || state.error != nil else { return }
        state = .loading
        let normalizedQueries = normalizeQueryKeys(nameQueries)
        guard !normalizedQueries.isEmpty else {
            handleLoadFailure(
                message: "No TLE query keys are configured.",
                clearsExistingDataOnFailure: clearsExistingDataOnFailure,
                showsRefreshFailureNotice: showsRefreshFailureNotice
            )
            return
        }

        do {
            var partialResults: [TLERepositoryResult] = []
            partialResults.reserveCapacity(normalizedQueries.count)
            for query in normalizedQueries {
                let result = try await handler(query)
                partialResults.append(result)
            }

            let mergedResult = mergeRepositoryResults(partialResults)
            tles = mergedResult.tles.sorted { lhs, rhs in
                switch (lhs.name, rhs.name) {
                case let (left?, right?):
                    return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return false
                }
            }
            lastFetchedAt = mergedResult.fetchedAt
            dataAge = now().timeIntervalSince(mergedResult.fetchedAt)
            state = .loaded(tles)
        } catch let error as CelesTrakError {
            handleLoadFailure(
                message: error.localizedDescription,
                clearsExistingDataOnFailure: clearsExistingDataOnFailure,
                showsRefreshFailureNotice: showsRefreshFailureNotice
            )
        } catch {
            handleLoadFailure(
                message: "An unexpected error occurred: \(error)",
                clearsExistingDataOnFailure: clearsExistingDataOnFailure,
                showsRefreshFailureNotice: showsRefreshFailureNotice
            )
        }
    }

    /// Handles load failures while respecting whether old data should remain visible.
    ///
    /// For manual refresh, this method keeps existing TLE data on-screen so users
    /// are not penalized with an empty state just because one request failed.
    private func handleLoadFailure(
        message: String,
        clearsExistingDataOnFailure: Bool,
        showsRefreshFailureNotice: Bool
    ) {
        if !clearsExistingDataOnFailure, !tles.isEmpty {
            state = .loaded(tles)
            if showsRefreshFailureNotice {
                refreshNotice = makeRefreshFailureNotice(message: message)
            }
            return
        }

        state = .error(message)
        tles = []
        lastFetchedAt = nil
        dataAge = nil
    }

    /// Builds plain-English guidance for users who tap refresh before cooldown ends.
    ///
    /// This remains internal so runtime code and preview code can reuse the
    /// exact same copy and time-formatting behavior.
    func manualRefreshCooldownNotice(nextAllowedRefreshDate: Date) -> RefreshNotice {
        let cooldownMinutes = max(1, Int((manualRefreshInterval / 60).rounded()))
        let availableAtText = refreshTimeText(for: nextAllowedRefreshDate)
        let relativeAvailableText = relativeTimeText(for: nextAllowedRefreshDate)
        let existingDataText = tles.isEmpty
            ? "No previously downloaded TLE set is available yet."
            : "Your current TLE set stays visible until a new refresh succeeds."

        return RefreshNotice(
            title: "Refresh Limited",
            message: """
            Manual refresh is available once every \(cooldownMinutes) minutes.

            Why this limit exists:
            - It protects the CelesTrak API from rate limiting.
            - TLE sets usually update only a few times each day.
            - The app also attempts automatic background refresh when cached data becomes stale.

            Next refresh: \(availableAtText) (\(relativeAvailableText)).

            \(existingDataText)
            """
        )
    }

    /// Builds a notice shown when an allowed manual refresh attempt fails.
    ///
    /// This keeps communication user-friendly while preserving older data on screen.
    private func makeRefreshFailureNotice(message: String) -> RefreshNotice {
        let detailText: String
        if let lastFetchedAt {
            detailText = "The app kept your previous TLE set from \(refreshTimeText(for: lastFetchedAt))."
        } else {
            detailText = "No local TLE data is available yet, so the list stays empty until the next successful fetch."
        }

        return RefreshNotice(
            title: "Refresh Unavailable",
            message: "\(message)\n\n\(detailText)"
        )
    }

    /// Builds a short absolute time string for user-facing refresh guidance.
    ///
    /// The formatter omits the date when the timestamp is today to keep alerts compact.
    private func refreshTimeText(for date: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now()) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Builds a short relative time string used in cooldown guidance.
    ///
    /// This avoids second-level noise so the toolbar and alert stay visually consistent.
    private func relativeTimeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: now())
    }

    /// Records a manual refresh tap and persists it for future app sessions.
    ///
    /// Persisting the timestamp prevents users from bypassing cooldown by
    /// killing and reopening the app or recreating the view model.
    private func recordManualRefreshAttempt(at date: Date) {
        lastManualRefreshAttemptAt = date
        cooldownPersistence.saveLastAttempt(date)
    }

    /// Restores persisted cooldown state on initialization when still valid.
    ///
    /// If the stored cooldown has already expired, this method clears it so
    /// future startups begin from a clean state.
    private func restorePersistedManualRefreshAttemptIfNeeded() {
        guard let persistedAttempt = cooldownPersistence.loadLastAttempt() else {
            lastManualRefreshAttemptAt = nil
            return
        }

        let persistedExpiry = persistedAttempt.addingTimeInterval(manualRefreshInterval)
        if persistedExpiry > now() {
            lastManualRefreshAttemptAt = persistedAttempt
        } else {
            lastManualRefreshAttemptAt = nil
            cooldownPersistence.clearLastAttempt()
        }
    }

    /// Deduplicates repeated query keys while preserving the user's input order.
    private func normalizeQueryKeys(_ nameQueries: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for query in nameQueries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let uppercase = trimmed.uppercased()
            if seen.insert(uppercase).inserted {
                normalized.append(trimmed)
            }
        }
        return normalized
    }

    /// Merges multiple repository results into one deduplicated payload.
    private func mergeRepositoryResults(_ results: [TLERepositoryResult]) -> TLERepositoryResult {
        var seenNoradIDs = Set<Int>()
        var seenFallbackKeys = Set<String>()
        var mergedTLEs: [TLE] = []
        mergedTLEs.reserveCapacity(results.reduce(0) { $0 + $1.tles.count })

        for result in results {
            for tle in result.tles {
                if let noradID = SatelliteIDParser.parseNoradId(line1: tle.line1) {
                    guard seenNoradIDs.insert(noradID).inserted else { continue }
                    mergedTLEs.append(tle)
                    continue
                }

                let fallbackKey = "\(tle.line1)|\(tle.line2)"
                guard seenFallbackKeys.insert(fallbackKey).inserted else { continue }
                mergedTLEs.append(tle)
            }
        }

        let latestFetchedAt = results.map(\.fetchedAt).max() ?? now()
        let mergedSource: TLERepositoryResult.Source = results.contains(where: { $0.source == .network }) ? .network : .cache
        return TLERepositoryResult(tles: mergedTLEs, fetchedAt: latestFetchedAt, source: mergedSource)
    }
}
