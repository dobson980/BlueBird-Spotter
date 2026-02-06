//
//  TLEBackgroundRefreshSchedulerTests.swift
//  BlueBird SpotterTests
//
//  Created by Tom Dobson on 12/21/25.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Verifies scheduling decisions without invoking BackgroundTasks directly.
struct TLEBackgroundRefreshSchedulerTests {
    @Test func schedulesWhenStaleAndNotRecentlyScheduled() {
        let policy = TLECachePolicy(staleAfter: 60)
        let scheduler = TLEBackgroundRefreshScheduler(minimumInterval: 2 * 60 * 60)
        let now = Date()
        let fetchedAt = now.addingTimeInterval(-120)

        let decision = scheduler.decision(
            fetchedAt: fetchedAt,
            lastScheduledAt: now.addingTimeInterval(-3 * 60 * 60),
            now: now,
            policy: policy
        )

        #expect(decision.shouldSchedule == true)
        #expect(decision.earliestBeginDate == now)
    }

    @Test func doesNotScheduleWhenFresh() {
        let policy = TLECachePolicy(staleAfter: 6 * 60 * 60)
        let scheduler = TLEBackgroundRefreshScheduler(minimumInterval: 2 * 60 * 60)
        let now = Date()
        let fetchedAt = now.addingTimeInterval(-60)

        let decision = scheduler.decision(
            fetchedAt: fetchedAt,
            lastScheduledAt: now.addingTimeInterval(-3 * 60 * 60),
            now: now,
            policy: policy
        )

        #expect(decision.shouldSchedule == false)
        #expect(decision.earliestBeginDate == nil)
    }

    @Test func enforcesMinimumIntervalBetweenSchedules() {
        let policy = TLECachePolicy(staleAfter: 60)
        let scheduler = TLEBackgroundRefreshScheduler(minimumInterval: 2 * 60 * 60)
        let now = Date()
        let fetchedAt = now.addingTimeInterval(-120)

        let decision = scheduler.decision(
            fetchedAt: fetchedAt,
            lastScheduledAt: now.addingTimeInterval(-60 * 60),
            now: now,
            policy: policy
        )

        #expect(decision.shouldSchedule == false)
        #expect(decision.earliestBeginDate == nil)
    }
}
