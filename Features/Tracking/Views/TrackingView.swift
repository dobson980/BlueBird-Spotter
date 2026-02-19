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
    /// Stores collapsed section IDs so users can hide groups they are not inspecting.
    @State private var collapsedSectionIDs: Set<String> = []
    /// Shared navigation state for cross-tab focus.
    @Environment(AppNavigationState.self) private var navigationState
    /// Tracks light/dark mode for adaptive styling.
    @Environment(\.colorScheme) private var colorScheme
    /// Query keys used to drive the tracking session.
    private let queryKeys = SatelliteProgramCatalog.defaultQueryKeys

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
                            viewModel.startTracking(queryKeys: queryKeys)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .disabled(viewModel.state.isLoading)
                        .accessibilityLabel("Refresh Tracking")
                    }
                }
        }
        .task {
            guard !isPreview else { return }
            // Begin tracking when the view becomes active.
            viewModel.startTracking(queryKeys: queryKeys)
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
                let groupedSatellites = groupedTrackedSatellites(trackedSatellites)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if #available(iOS 26.0, macOS 26.0, *) {
                            GlassEffectContainer(spacing: 12) {
                                sectionRows(for: groupedSatellites)
                            }
                        } else {
                            sectionRows(for: groupedSatellites)
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
        .padding(16)
        .frame(maxWidth: 320)
        .blueBirdHUDCard(
            cornerRadius: 16,
            tint: showError ? .red : Color(red: 0.04, green: 0.61, blue: 0.86)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    /// Builds a collapsible section header so users can focus on one category at a time.
    private func sectionHeader(
        title: String,
        count: Int,
        isCollapsed: Bool,
        action: @escaping () -> Void
    ) -> some View {
        BlueBirdCollapsibleSectionHeader(
            title: title,
            count: count,
            isCollapsed: isCollapsed,
            action: action
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    /// Reusable section renderer so list composition can opt into `GlassEffectContainer`.
    @ViewBuilder
    private func sectionRows(for groupedSatellites: [TrackingSection]) -> some View {
        ForEach(groupedSatellites) { section in
            let isCollapsed = collapsedSectionIDs.contains(section.id)

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: section.category.label,
                    count: section.satellites.count,
                    isCollapsed: isCollapsed
                ) {
                    toggleSection(sectionID: section.id)
                }

                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(section.satellites) { tracked in
                            TrackingSatelliteCard(tracked: tracked)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Tap a row to jump to the globe and focus the satellite.
                                    navigationState.focusOnSatellite(id: tracked.satellite.id)
                                }
                        }
                    }
                    // Keep expansion visually anchored under the section label.
                    .transition(.opacity)
                }
            }
        }
    }

    /// Expands or collapses a category section with a short animation.
    private func toggleSection(sectionID: String) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if collapsedSectionIDs.contains(sectionID) {
                collapsedSectionIDs.remove(sectionID)
            } else {
                collapsedSectionIDs.insert(sectionID)
            }
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

    /// Groups tracked satellites by category for easier visual scanning.
    private func groupedTrackedSatellites(_ satellites: [TrackedSatellite]) -> [TrackingSection] {
        let grouped = Dictionary(grouping: satellites) { tracked in
            SatelliteProgramCatalog.descriptor(for: tracked.satellite).category
        }

        return grouped
            .map { category, satellites in
                TrackingSection(
                    category: category,
                    satellites: satellites.sorted { left, right in
                        let leftDisplayName = SatelliteProgramCatalog.descriptor(for: left.satellite).displayName
                        let rightDisplayName = SatelliteProgramCatalog.descriptor(for: right.satellite).displayName
                        return leftDisplayName.localizedCaseInsensitiveCompare(rightDisplayName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.category < $1.category }
    }

    /// Detects when the view is running in Xcode previews.
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

/// Preview for validating tracking cards with realistic telemetry values.
#Preview("Loaded") {
    TrackingView(viewModel: .previewLoadedModel())
        // Inject navigation state so selection taps resolve the same as the running app.
        .environment(AppNavigationState())
}

/// Preview for checking the loading state before tracking starts.
#Preview("Loading") {
    TrackingView(viewModel: .previewLoadingModel())
        .environment(AppNavigationState())
}

/// Preview for checking long error messages and empty-state spacing.
#Preview("Error") {
    TrackingView(viewModel: .previewErrorModel())
        .environment(AppNavigationState())
}
