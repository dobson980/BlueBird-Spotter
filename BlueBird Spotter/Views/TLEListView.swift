//
//  TLEListView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import SwiftUI

/// Displays the TLE fetch workflow with a simple status-driven layout.
///
/// This view mirrors the existing list UI while keeping the tab container
/// light-weight for navigation.
struct TLEListView: View {
    /// Local view model state so the UI refreshes when data changes.
    @State private var viewModel: CelesTrakViewModel

    /// Allows previews to inject a prepared view model.
    init(viewModel: CelesTrakViewModel = CelesTrakViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header icon to anchor the simple demo layout.
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Group {
                switch viewModel.state {
                case .idle:
                    Text("No TLEs loaded.")
                case .loading:
                    ProgressView("Loading TLEs...")
                case .loaded(let tles):
                    // Show a lightweight freshness hint above the list.
                    if let lastFetchedAt = viewModel.lastFetchedAt {
                        Text("Last refreshed: \(lastFetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Primary results list; each row shows name and both TLE lines.
                    List(tles, id: \.line1) { tle in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tle.name ?? "Unnamed satellite")
                                .font(.headline)
                            Text(tle.line1)
                                .font(.caption)
                                .monospaced()
                            Text(tle.line2)
                                .font(.caption)
                                .monospaced()
                        }
                    }
                case .error(let message):
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .task {
            guard !isPreview else { return }
            // Trigger a sample query when the view appears.
            await viewModel.fetchTLEs(nameQuery: "SPACEMOBILE")
        }
        .padding()
    }

    /// Detects when the view is running in Xcode previews.
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

/// Preview for quickly checking the TLE list layout in Xcode.
#Preview {
    TLEListView(viewModel: .previewModel())
}

private extension CelesTrakViewModel {
    /// Provides sample data for previewing the TLE list without network access.
    static func previewModel() -> CelesTrakViewModel {
        let viewModel = CelesTrakViewModel()
        let sampleTles = [
            TLE(name: "BLUEBIRD-1", line1: "1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991", line2: "2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456"),
            TLE(name: "BLUEBIRD-2", line1: "1 00002U 98067A   20344.22345678  .00001234  00000-0  10270-3 0  9992", line2: "2 00002  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456")
        ]
        viewModel.tles = sampleTles
        viewModel.state = .loaded(sampleTles)
        viewModel.lastFetchedAt = Date()
        viewModel.dataAge = 120
        return viewModel
    }
}
