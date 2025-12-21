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
    /// Injected fetcher to support testing or alternate data sources.
    private let fetchHandler: @Sendable (String) async throws -> TLERepositoryResult

    /// Latest fetched list for views that want direct access.
    var tles: [TLE] = []
    /// UI-friendly load state for progress and error messaging.
    var state: LoadState<[TLE]> = .idle
    /// Timestamp from the data source, used for freshness display later.
    var lastFetchedAt: Date?
    /// Age of the data in seconds, computed when a result arrives.
    var dataAge: TimeInterval?

    /// Default initializer that uses the shared production repository.
    init(repository: TLERepository = TLERepository.shared) {
        self.fetchHandler = repository.getTLEs
    }

    /// Test-friendly initializer that injects a custom fetch closure.
    init(fetchHandler: @escaping @Sendable (String) async throws -> TLERepositoryResult) {
        self.fetchHandler = fetchHandler
    }

    /// Loads TLEs and updates state for the view layer.
    ///
    /// The method also sorts results alphabetically by satellite name.
    func fetchTLEs(nameQuery: String) async {
        guard !state.isLoading || state.error != nil else { return }
        state = .loading

        do {
            let result = try await fetchHandler(nameQuery)
            tles = result.tles.sorted { lhs, rhs in
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
            lastFetchedAt = result.fetchedAt
            dataAge = Date().timeIntervalSince(result.fetchedAt)
            state = .loaded(tles)
        } catch let error as CelesTrakError {
            state = .error(error.localizedDescription)
            tles = []
            lastFetchedAt = nil
            dataAge = nil
        } catch {
            state = .error("An unexpected error occurred: \(error)")
            tles = []
            lastFetchedAt = nil
            dataAge = nil
        }
    }
}
