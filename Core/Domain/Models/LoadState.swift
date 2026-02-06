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

    /// Convenience flag for spinners and disabled UI.
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Extracts the payload when the state is `.loaded`.
    var data: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    /// Extracts the error message when the state is `.error`.
    var error: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}
