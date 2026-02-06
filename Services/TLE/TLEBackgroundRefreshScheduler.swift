//
//  TLEBackgroundRefreshScheduler.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/21/25.
//

import Foundation

/// Decision output for background refresh scheduling.
struct TLEBackgroundRefreshDecision: Equatable, Sendable {
    nonisolated let shouldSchedule: Bool
    nonisolated let earliestBeginDate: Date?
}

/// Encapsulates scheduling rules for background TLE refresh tasks.
struct TLEBackgroundRefreshScheduler: Sendable {
    /// Minimum interval between scheduled tasks to avoid excessive fetches.
    nonisolated let minimumInterval: TimeInterval

    nonisolated init(minimumInterval: TimeInterval = 2 * 60 * 60) {
        self.minimumInterval = minimumInterval
    }

    /// Determines whether a background refresh should be scheduled.
    ///
    /// The decision uses cache staleness as the primary signal and
    /// enforces the minimum interval between schedule requests.
    nonisolated func decision(
        fetchedAt: Date?,
        lastScheduledAt: Date?,
        now: Date,
        policy: TLECachePolicy
    ) -> TLEBackgroundRefreshDecision {
        let isStale = fetchedAt.map { policy.isStale(fetchedAt: $0, now: now) } ?? true
        guard isStale else {
            return TLEBackgroundRefreshDecision(shouldSchedule: false, earliestBeginDate: nil)
        }

        if let lastScheduledAt, now.timeIntervalSince(lastScheduledAt) < minimumInterval {
            return TLEBackgroundRefreshDecision(shouldSchedule: false, earliestBeginDate: nil)
        }

        return TLEBackgroundRefreshDecision(shouldSchedule: true, earliestBeginDate: now)
    }
}
