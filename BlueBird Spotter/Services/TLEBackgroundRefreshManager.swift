//
//  TLEBackgroundRefreshManager.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import BackgroundTasks
import Foundation

/// Coordinates BGTask scheduling and execution for TLE refreshes.
@MainActor
final class TLEBackgroundRefreshManager {
    static let shared = TLEBackgroundRefreshManager()

    /// Background task identifier registered with the system.
    let taskIdentifier = "DobsonLabs.BlueBird-Spotter.refreshTLE"

    private let repository: TLERepository
    private let cacheStore: TLECacheStore
    private let policy: TLECachePolicy
    private let scheduler: TLEBackgroundRefreshScheduler
    private let userDefaults: UserDefaults
    private let clock: @Sendable () -> Date

    private let lastScheduledKey = "BlueBirdSpotter.LastBackgroundRefreshSchedule"

    init(
        repository: TLERepository = TLERepository.shared,
        cacheStore: TLECacheStore = TLECacheStore(),
        policy: TLECachePolicy = TLECachePolicy(),
        scheduler: TLEBackgroundRefreshScheduler = TLEBackgroundRefreshScheduler(),
        userDefaults: UserDefaults = .standard,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.cacheStore = cacheStore
        self.policy = policy
        self.scheduler = scheduler
        self.userDefaults = userDefaults
        self.clock = clock
    }

    /// Registers the background task handler on app launch.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleRefresh(task: refreshTask)
        }
    }

    /// Schedules a background refresh when cached data is stale.
    func scheduleIfNeeded(queryKey: String) async {
        let fetchedAt = await cachedFetchDate(for: queryKey)
        let now = clock()
        let decision = scheduler.decision(
            fetchedAt: fetchedAt,
            lastScheduledAt: lastScheduledAt(),
            now: now,
            policy: policy
        )

        guard decision.shouldSchedule else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = decision.earliestBeginDate

        do {
            try BGTaskScheduler.shared.submit(request)
            storeLastScheduled(at: now)
        } catch {
            // Scheduling failures are non-fatal; they just defer to the next opportunity.
        }
    }

    /// Executes a background refresh and signals completion to the system.
    private func handleRefresh(task: BGAppRefreshTask) {
        let refreshTask = Task { [weak self] in
            guard let self else { return false }
            do {
                let result = try await repository.refreshTLEs(queryKey: "SPACEMOBILE")
                await scheduleIfNeeded(queryKey: "SPACEMOBILE")
                return result.source == .network
            } catch {
                await scheduleIfNeeded(queryKey: "SPACEMOBILE")
                return false
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            let success = await refreshTask.value
            task.setTaskCompleted(success: success)
        }
    }

    /// Reads the cached fetch date for scheduling decisions.
    private func cachedFetchDate(for queryKey: String) async -> Date? {
        do {
            return try await cacheStore.load(queryKey: queryKey)?.metadata.fetchedAt
        } catch {
            return nil
        }
    }

    /// Retrieves the last scheduled date from persistent storage.
    private func lastScheduledAt() -> Date? {
        let value = userDefaults.double(forKey: lastScheduledKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// Persists the last scheduled date to enforce the minimum interval.
    private func storeLastScheduled(at date: Date) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastScheduledKey)
    }
}
