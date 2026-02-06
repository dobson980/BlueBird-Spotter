//
//  TrackingTicker.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation

/// Abstraction for producing time ticks used by the tracking loop.
protocol TrackingTicker: Sendable {
    /// Creates an async stream of timestamps for each tracking update.
    ///
    /// Nonisolated so consumers can iterate off the main actor.
    nonisolated func ticks() -> AsyncStream<Date>
}

/// Production ticker that emits a timestamp at a fixed interval.
struct RealTimeTicker: TrackingTicker {
    /// Interval in seconds between updates.
    private let interval: TimeInterval

    /// Default initializer tuned for 1Hz tracking updates.
    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    nonisolated func ticks() -> AsyncStream<Date> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(Date())
                    let nanoseconds = UInt64(interval * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
