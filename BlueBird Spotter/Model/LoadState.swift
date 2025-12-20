//
//  LoadState.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

/// Simple dependency-free state machine shared by view models.
enum LoadState<Value>: Equatable where Value: Equatable {
    case idle
    case loading
    case loaded(Value)
    case error(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var data: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}
