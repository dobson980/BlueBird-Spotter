//
//  TrackingView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import SwiftUI

/// Presents the live tracking loop output for each satellite.
///
/// The layout emphasizes a quick glance at name, location, and update time.
struct TrackingView: View {
    /// Local view model state so the UI refreshes with tracking updates.
    @State private var viewModel: TrackingViewModel
    /// Tracks light/dark mode for adaptive styling.
    @Environment(\.colorScheme) private var colorScheme
    /// Fixed query key used to drive the tracking session.
    private let queryKey = "SPACEMOBILE"

    /// Allows previews to inject a prepared view model.
    init(viewModel: TrackingViewModel = TrackingViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                spaceBackground
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        titleStack
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.startTracking(queryKey: queryKey)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.state.isLoading)
                        .accessibilityLabel("Refresh Tracking")
                    }
                }
        }
        .task {
            guard !isPreview else { return }
            // Begin tracking when the view becomes active.
            viewModel.startTracking(queryKey: queryKey)
        }
        .onDisappear {
            // Stop background work when the tab is no longer visible.
            viewModel.stopTracking()
        }
    }

    /// Main content that switches between loading, error, and list states.
    private var content: some View {
        Group {
            switch viewModel.state {
            case .idle:
                emptyState(text: "Tracking is idle.")
            case .loading:
                emptyState(text: "Starting tracking...", showSpinner: true)
            case .loaded(let trackedSatellites):
                // Match the TLE tab by sorting alphabetically by satellite name.
                let sortedSatellites = sortTrackedSatellites(trackedSatellites)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sortedSatellites) { tracked in
                            trackingRow(tracked)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                // Safe-area padding keeps telemetry cards above the tab bar.
                .safeAreaPadding(.bottom, 16)
            case .error(let message):
                emptyState(text: message, showError: true)
            }
        }
    }

    /// Builds a compact, space-inspired title stack with TLE refresh timing.
    private var titleStack: some View {
        VStack(spacing: 2) {
            Text("Tracking")
                .font(.headline.weight(.semibold))

            if let lastFetchedAt = viewModel.lastTLEFetchedAt {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                    Text("Last Updated")
                    Text(lastFetchedAt, style: .relative)
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if viewModel.state.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Updating…")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Shared empty/error layout for non-list states.
    private func emptyState(text: String, showSpinner: Bool = false, showError: Bool = false) -> some View {
        VStack(spacing: 12) {
            if showSpinner {
                ProgressView()
            } else {
                Image(systemName: showError ? "exclamationmark.triangle.fill" : "sparkles")
                    .foregroundStyle(showError ? .red : .secondary)
            }
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(showError ? .red : .secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Rounds degrees for a compact UI-friendly readout.
    private func formatDegrees(_ value: Double) -> String {
        String(format: "%.2f°", value)
    }

    /// Rounds kilometers for a compact UI-friendly readout.
    private func formatKilometers(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Builds a card-style row that highlights live tracking values with equal-width chips.
    private func trackingRow(_ tracked: TrackedSatellite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .padding(6)
                    .background(.thinMaterial, in: Circle())

                Text(tracked.satellite.name)
                    .font(.headline)
            }

            statGrid(for: tracked)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background { primaryCardBackground(cornerRadius: 16) }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardBorderGradient, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(highlightGradient)
                .frame(width: 120, height: 2)
                .padding(.top, 8)
                .padding(.leading, 12)
                .opacity(0.6)
        }
        .shadow(color: cardShadowColor, radius: 4, x: 0, y: 2)
        .clipped()
    }

    /// Picks a grid density that fits the available width so chips stay on-screen.
    private func statGrid(for tracked: TrackedSatellite) -> some View {
        // ViewThatFits tries layouts in order and selects the first that fits.
        ViewThatFits(in: .horizontal) {
            statGrid(columns: 3, tracked: tracked)
            statGrid(columns: 2, tracked: tracked)
            statGrid(columns: 1, tracked: tracked)
        }
    }

    /// Builds the requested grid column count for the telemetry chips.
    private func statGrid(columns count: Int, tracked: TrackedSatellite) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
        return LazyVGrid(columns: columns, spacing: 8) {
            statChip(label: "Lat", value: formatDegrees(tracked.position.latitudeDegrees))
            statChip(label: "Lon", value: formatDegrees(tracked.position.longitudeDegrees))
            statChip(label: "Alt", value: "\(formatKilometers(tracked.position.altitudeKm)) km")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Builds a compact chip for a single telemetry value.
    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            secondaryCardBackground(cornerRadius: 10)
        }
    }

    /// Full-screen space backdrop shared across tabs.
    private var spaceBackground: some View {
        GeometryReader { geometry in
            Image("space")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.0))
        }
        .ignoresSafeArea()
    }

    /// Primary card background with adaptive material for light/dark modes.
    @ViewBuilder
    private func primaryCardBackground(cornerRadius: CGFloat) -> some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.45))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.7))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Secondary inset background that frames each telemetry chip.
    @ViewBuilder
    private func secondaryCardBackground(cornerRadius: CGFloat) -> some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.03))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.06))
        }
    }

    /// Soft neon border that is stronger in dark mode and subtle in light mode.
    private var cardBorderGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    .white.opacity(0.06),
                    .cyan.opacity(0.08),
                    .purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                .black.opacity(0.08),
                .cyan.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Glow tint that stays restrained in light mode.
    private var cardShadowColor: Color {
        colorScheme == .dark ? .cyan.opacity(0.015) : .cyan.opacity(0.008)
    }

    /// Subtle highlight used for the top accent line.
    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                .cyan.opacity(colorScheme == .dark ? 0.25 : 0.15),
                .purple.opacity(colorScheme == .dark ? 0.18 : 0.1),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Sorts tracked satellites alphabetically so the tracking list mirrors the TLE tab.
    private func sortTrackedSatellites(_ satellites: [TrackedSatellite]) -> [TrackedSatellite] {
        satellites.sorted { left, right in
            left.satellite.name.localizedCaseInsensitiveCompare(right.satellite.name) == .orderedAscending
        }
    }

    /// Detects when the view is running in Xcode previews.
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

/// Preview for validating tracking layout without live data.
#Preview {
    TrackingView(viewModel: .previewModel())
}

private extension TrackingViewModel {
    /// Provides sample data for previewing tracking without network access.
    static func previewModel() -> TrackingViewModel {
        let viewModel = TrackingViewModel()
        let now = Date()
        let sampleSatellite = Satellite(
            id: 12345,
            name: "BLUEBIRD-TRACK",
            tleLine1: "1 12345U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991",
            tleLine2: "2 12345  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456",
            epoch: now
        )
        let samplePosition = SatellitePosition(
            timestamp: now,
            latitudeDegrees: 37.77,
            longitudeDegrees: -122.42,
            altitudeKm: 550.2
        )
        let tracked = [TrackedSatellite(satellite: sampleSatellite, position: samplePosition)]
        viewModel.trackedSatellites = tracked
        viewModel.state = .loaded(tracked)
        viewModel.lastUpdatedAt = now
        viewModel.lastTLEFetchedAt = now
        return viewModel
    }
}
