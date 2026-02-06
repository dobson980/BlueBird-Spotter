//
//  TLECachePolicy.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation

/// Encapsulates how long cached TLE data is considered fresh.
struct TLECachePolicy: Sendable, Equatable {
    /// Duration after which cached data is treated as stale.
    var staleAfter: TimeInterval = 6 * 60 * 60

    /// Returns true when the cache age exceeds the policy threshold.
    nonisolated func isStale(fetchedAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) >= staleAfter
    }
}
