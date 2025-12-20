//
//  CelesTrakViewModel.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import Foundation
import Observation

@MainActor
@Observable
final class CelesTrakViewModel {
    private let service: any CelesTrakTLEService

    var tles: [TLE] = []
    var state: LoadState<[TLE]> = .idle

    init(service: any CelesTrakTLEService = CelesTrakTLEClient()) {
        self.service = service
    }

    func fetchTLEs(nameQuery: String) async {
        guard !state.isLoading || state.error != nil else { return }
        state = .loading

        do {
            let fetched = try await service.fetchTLEs(nameQuery: nameQuery)
            tles = fetched.sorted { lhs, rhs in
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
            state = .loaded(tles)
        } catch let error as CelesTrakError {
            state = .error(error.localizedDescription)
            tles = []
        } catch {
            state = .error("An unexpected error occurred: \(error)")
            tles = []
        }
    }
}
