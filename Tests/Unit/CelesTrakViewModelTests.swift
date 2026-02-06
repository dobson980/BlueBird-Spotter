//
//  CelesTrakViewModelTests.swift
//  BlueBird SpotterTests
//
//  Created by Codex on 2/6/26.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Unit tests for TLE list ViewModel state transitions.
///
/// These tests focus on load orchestration and error handling so contributors
/// can refactor UI safely without changing data behavior.
struct CelesTrakViewModelTests {
    /// Tracks how many times an injected handler is executed.
    private actor CallCounter {
        private var count = 0

        func increment() {
            count += 1
        }

        func value() -> Int {
            count
        }
    }

    /// Builds a deterministic repository result for view model tests.
    private func makeResult(names: [String?], fetchedAt: Date) -> TLERepositoryResult {
        TLERepositoryResult(
            tles: names.enumerated().map { index, name in
                TLE(name: name, line1: "1 \(index)", line2: "2 \(index)")
            },
            fetchedAt: fetchedAt,
            source: .network
        )
    }

    /// Confirms fetch sorts names and publishes metadata for the UI.
    @Test @MainActor func fetchTLEs_success_sortsAndPublishesMetadata() async {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let result = makeResult(names: ["Zulu", nil, "alpha"], fetchedAt: fetchedAt)
        let viewModel = CelesTrakViewModel(fetchHandler: { _ in result })

        await viewModel.fetchTLEs(nameQuery: "SPACEMOBILE")

        #expect(viewModel.tles.map { $0.name } == ["alpha", "Zulu", nil])
        #expect(viewModel.state.data == viewModel.tles)
        #expect(viewModel.lastFetchedAt == fetchedAt)
        #expect(viewModel.dataAge != nil)
    }

    /// Confirms duplicate fetch calls are ignored while loading is already active.
    @Test @MainActor func fetchTLEs_ignoresDuplicateWhenAlreadyLoading() async {
        let counter = CallCounter()
        let result = makeResult(names: ["Only"], fetchedAt: Date(timeIntervalSince1970: 1_000))
        let viewModel = CelesTrakViewModel(fetchHandler: { _ in
            await counter.increment()
            return result
        })
        viewModel.state = .loading

        await viewModel.fetchTLEs(nameQuery: "SPACEMOBILE")

        #expect(await counter.value() == 0)
        #expect(viewModel.state.isLoading)
    }

    /// Confirms typed errors are surfaced and stale values are cleared.
    @Test @MainActor func fetchTLEs_onTypedError_setsErrorAndClearsState() async {
        let viewModel = CelesTrakViewModel(fetchHandler: { _ in
            throw CelesTrakError.badStatus(500)
        })

        await viewModel.fetchTLEs(nameQuery: "SPACEMOBILE")

        #expect(viewModel.tles.isEmpty)
        #expect(viewModel.lastFetchedAt == nil)
        #expect(viewModel.dataAge == nil)
        #expect(viewModel.state.error?.contains("status code 500") == true)
    }

    /// Confirms refresh uses the dedicated refresh handler instead of fetch handler.
    @Test @MainActor func refreshTLEs_usesRefreshHandler() async {
        let fetchResult = makeResult(names: ["From Fetch"], fetchedAt: Date(timeIntervalSince1970: 2_000))
        let refreshResult = makeResult(names: ["From Refresh"], fetchedAt: Date(timeIntervalSince1970: 3_000))

        let viewModel = CelesTrakViewModel(
            fetchHandler: { _ in fetchResult },
            refreshHandler: { _ in refreshResult }
        )

        await viewModel.fetchTLEs(nameQuery: "SPACEMOBILE")
        #expect(viewModel.tles.first?.name == "From Fetch")

        await viewModel.refreshTLEs(nameQuery: "SPACEMOBILE")
        #expect(viewModel.tles.first?.name == "From Refresh")
        #expect(viewModel.lastFetchedAt == refreshResult.fetchedAt)
    }

    /// Confirms rapid repeat taps are blocked to protect the upstream API quota.
    @Test @MainActor func refreshTLEs_withinCooldown_setsNoticeAndSkipsNetwork() async {
        let refreshCounter = CallCounter()
        let refreshResult = makeResult(names: ["From Refresh"], fetchedAt: Date(timeIntervalSince1970: 4_000))
        let viewModel = CelesTrakViewModel(
            fetchHandler: { _ in refreshResult },
            refreshHandler: { _ in
                await refreshCounter.increment()
                return refreshResult
            }
        )

        await viewModel.refreshTLEs(nameQuery: "SPACEMOBILE")
        let firstRefreshFetchedAt = viewModel.lastFetchedAt
        await viewModel.refreshTLEs(nameQuery: "SPACEMOBILE")

        #expect(await refreshCounter.value() == 1)
        #expect(viewModel.refreshNotice?.title == "Refresh Limited")
        #expect(viewModel.refreshNotice?.message.contains("few times each day") == true)
        #expect(viewModel.refreshNotice?.message.contains("automatic background refresh") == true)
        #expect(viewModel.lastFetchedAt == firstRefreshFetchedAt)
        #expect(viewModel.state.data == viewModel.tles)
    }

    /// Confirms a new manual refresh is allowed again once cooldown expires.
    @Test @MainActor func refreshTLEs_afterCooldown_allowsSecondNetworkCall() async {
        let refreshCounter = CallCounter()
        let refreshResult = makeResult(names: ["From Refresh"], fetchedAt: Date(timeIntervalSince1970: 5_000))
        let viewModel = CelesTrakViewModel(
            fetchHandler: { _ in refreshResult },
            refreshHandler: { _ in
                await refreshCounter.increment()
                return refreshResult
            },
            manualRefreshInterval: 0.01
        )

        await viewModel.refreshTLEs(nameQuery: "SPACEMOBILE")
        try? await Task.sleep(nanoseconds: 30_000_000)
        await viewModel.refreshTLEs(nameQuery: "SPACEMOBILE")

        #expect(await refreshCounter.value() == 2)
        #expect(viewModel.refreshNotice == nil)
    }

    /// Confirms failed manual refresh keeps older TLE data visible to the user.
    @Test @MainActor func refreshTLEs_onError_keepsExistingDataAndShowsNotice() async {
        let fetchedAt = Date(timeIntervalSince1970: 6_000)
        let fetchResult = makeResult(names: ["From Fetch"], fetchedAt: fetchedAt)
        let viewModel = CelesTrakViewModel(
            fetchHandler: { _ in fetchResult },
            refreshHandler: { _ in
                throw CelesTrakError.badStatus(503)
            }
        )

        await viewModel.fetchTLEs(nameQuery: "SPACEMOBILE")
        let originalTLEs = viewModel.tles
        let originalFetchedAt = viewModel.lastFetchedAt
        await viewModel.refreshTLEs(nameQuery: "SPACEMOBILE")

        #expect(viewModel.tles == originalTLEs)
        #expect(viewModel.state.data == originalTLEs)
        #expect(viewModel.lastFetchedAt == originalFetchedAt)
        #expect(viewModel.refreshNotice?.title == "Refresh Unavailable")
        #expect(viewModel.refreshNotice?.message.contains("status code 503") == true)
    }
}
