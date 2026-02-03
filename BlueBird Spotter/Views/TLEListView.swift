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
    /// Tracks light/dark mode for adaptive styling.
    @Environment(\.colorScheme) private var colorScheme
    /// Fixed query key used across the demo views.
    private let queryKey = "SPACEMOBILE"

    /// Allows previews to inject a prepared view model.
    init(viewModel: CelesTrakViewModel = CelesTrakViewModel()) {
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
                            Task {
                                await viewModel.refreshTLEs(nameQuery: queryKey)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.state.isLoading)
                        .accessibilityLabel("Refresh TLEs")
                    }
                }
        }
        .task {
            guard !isPreview else { return }
            // Trigger a sample query when the view appears.
            await viewModel.fetchTLEs(nameQuery: queryKey)
        }
    }

    /// Main content that switches between loading, error, and list states.
    private var content: some View {
        Group {
            switch viewModel.state {
            case .idle:
                emptyState(text: "No TLEs loaded.")
            case .loading:
                emptyState(text: "Loading TLEs...", showSpinner: true)
            case .loaded(let tles):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(tles, id: \.line1) { tle in
                            tleRow(tle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                // Safe-area padding keeps cards above the tab bar without hard-coded heights.
                .safeAreaPadding(.bottom, 16)
            case .error(let message):
                emptyState(text: message, showError: true)
            }
        }
    }

    /// Builds a compact, space-inspired title stack with refresh timing.
    private var titleStack: some View {
        VStack(spacing: 2) {
            Text("TLEs")
                .font(.headline.weight(.semibold))

            if let lastFetchedAt = viewModel.lastFetchedAt {
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

    /// Builds a card-style row for a single TLE entry with a subtle space glow.
    private func tleRow(_ tle: TLE) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .padding(6)
                    .background(.thinMaterial, in: Circle())

                Text(tle.name ?? "Unnamed satellite")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                tleLine(tle.line1)
                tleLine(tle.line2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                secondaryCardBackground(cornerRadius: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            primaryCardBackground(cornerRadius: 16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardBorderGradient, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            // Thin highlight line adds a sci-fi HUD accent without heavy glow.
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

    /// Keeps fixed-width TLE strings readable without forcing the card wider than the screen.
    private func tleLine(_ line: String) -> some View {
        // Horizontal scrolling lets the full TLE line stay accessible without overflowing.
        ScrollView(.horizontal, showsIndicators: false) {
            Text(line)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Secondary inset background that frames the TLE lines.
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
