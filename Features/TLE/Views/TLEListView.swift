//
//  TLEListView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/20/25.
//

import Foundation
import SwiftUI

/// Displays the TLE fetch workflow with a simple status-driven layout.
///
/// This view mirrors the existing list UI while keeping the tab container
/// light-weight for navigation.
struct TLEListView: View {
    /// Local view model state so the UI refreshes when data changes.
    @State private var viewModel: CelesTrakViewModel
    /// Stores collapsed section IDs so users can hide categories they are not inspecting.
    @State private var collapsedSectionIDs: Set<String> = []
    /// Shared navigation state for cross-tab focus.
    @Environment(AppNavigationState.self) private var navigationState
    /// Tracks light/dark mode for adaptive styling.
    @Environment(\.colorScheme) private var colorScheme
    /// Query keys used across tabs, including BlueWalker 3.
    private let queryKeys = SatelliteProgramCatalog.defaultQueryKeys

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
                                await viewModel.refreshTLEs(nameQueries: queryKeys)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .disabled(viewModel.state.isLoading)
                        .accessibilityLabel("Refresh TLEs")
                    }
                }
        }
        .task {
            guard !isPreview else { return }
            // Trigger a sample query when the view appears.
            await viewModel.fetchTLEs(nameQueries: queryKeys)
        }
        .alert(
            viewModel.refreshNotice?.title ?? "Refresh Notice",
            isPresented: refreshNoticePresented
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearRefreshNotice()
            }
        } message: {
            Text(viewModel.refreshNotice?.message ?? "")
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
                let sections = groupedTLEs(tles)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if #available(iOS 26.0, macOS 26.0, *) {
                            GlassEffectContainer(spacing: 12) {
                                sectionRows(for: sections)
                            }
                        } else {
                            sectionRows(for: sections)
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
        VStack(spacing: 4) {
            Text("TLEs")
                .font(.headline.weight(.semibold))

            if let lastFetchedAt = viewModel.lastFetchedAt {
                refreshMetadataRow(
                    iconName: "sparkles",
                    label: "Last Updated",
                    value: viewModel.relativeRefreshTimeText(for: lastFetchedAt)
                )
            } else if viewModel.state.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 12, alignment: .center)
                    Text("Last Updated")
                        .frame(width: 82, alignment: .leading)
                    Text("Updating…")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let nextManualRefreshDate = viewModel.nextManualRefreshDate {
                // This hint teaches users why rapid manual refresh taps are throttled.
                refreshMetadataRow(
                    iconName: "clock",
                    label: "Next Refresh",
                    value: viewModel.relativeRefreshTimeText(for: nextManualRefreshDate)
                )
            }
        }
    }

    /// Renders one compact metadata row for title-area timing details.
    ///
    /// The fixed label width keeps "Last Updated" and "Next Refresh" values aligned.
    private func refreshMetadataRow(iconName: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 12, alignment: .center)
            Text(label)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
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

    /// Builds a collapsible section header that matches the shared HUD label style.
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
    private func sectionRows(for sections: [TLESection]) -> some View {
        ForEach(sections) { section in
            let isCollapsed = collapsedSectionIDs.contains(section.id)

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: section.category.label,
                    count: section.tles.count,
                    isCollapsed: isCollapsed
                ) {
                    toggleSection(sectionID: section.id)
                }

                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(section.tles, id: \.line1) { tle in
                            TLESatelliteCard(tle: tle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Tap a row to jump to the globe and focus the satellite.
                                    guard let id = SatelliteIDParser.parseNoradId(line1: tle.line1) else { return }
                                    navigationState.focusOnSatellite(id: id)
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

    /// Detects when the view is running in Xcode previews.
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Bridges optional `refreshNotice` state into SwiftUI's Boolean alert API.
    ///
    /// This keeps alert presentation logic in the view layer while the view model
    /// stays focused on policy decisions and user-facing message content.
    private var refreshNoticePresented: Binding<Bool> {
        Binding(
            get: { viewModel.refreshNotice != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearRefreshNotice()
                }
            }
        )
    }

    /// Groups TLE entries by satellite program category for easier scanning.
    private func groupedTLEs(_ tles: [TLE]) -> [TLESection] {
        let grouped = Dictionary(grouping: tles) { tle in
            SatelliteProgramCatalog.descriptor(forTLEName: tle.name, line1: tle.line1).category
        }

        return grouped
            .map { category, entries in
                TLESection(
                    category: category,
                    tles: entries.sorted(by: tleSort)
                )
            }
            .sorted { $0.category < $1.category }
    }

    /// Reuses the existing name-first ordering inside each category section.
    private func tleSort(_ lhs: TLE, _ rhs: TLE) -> Bool {
        let leftDisplayName = SatelliteProgramCatalog.descriptor(forTLEName: lhs.name, line1: lhs.line1).displayName
        let rightDisplayName = SatelliteProgramCatalog.descriptor(forTLEName: rhs.name, line1: rhs.line1).displayName
        let nameOrdering = leftDisplayName.localizedCaseInsensitiveCompare(rightDisplayName)
        if nameOrdering != .orderedSame {
            return nameOrdering == .orderedAscending
        }
        return lhs.line1 < rhs.line1
    }

}

/// Preview for quickly checking a successful TLE load state.
#Preview("Loaded") {
    TLEListView(viewModel: .previewLoadedModel())
        // Inject navigation state so row tap gestures can resolve environment lookups.
        .environment(AppNavigationState())
}

/// Preview for validating loading skeleton and toolbar disabled states.
#Preview("Loading") {
    TLEListView(viewModel: .previewLoadingModel())
        .environment(AppNavigationState())
}

/// Preview for validating readable error messaging.
#Preview("Error") {
    TLEListView(viewModel: .previewErrorModel())
        .environment(AppNavigationState())
}

/// Preview for reviewing manual refresh alert copy and wrapping behavior.
#Preview("Refresh Limited Alert") {
    TLERefreshLimitedAlertPreviewHarness()
        .environment(AppNavigationState())
}

/// Preview harness that triggers the alert after first render.
///
/// A delayed assignment forces a state transition, which makes alert previews
/// reliable in cases where Xcode does not present "already true" alerts.
private struct TLERefreshLimitedAlertPreviewHarness: View {
    @State private var viewModel = CelesTrakViewModel.previewLoadedModel()

    var body: some View {
        TLEListView(viewModel: viewModel)
            .task {
                guard viewModel.refreshNotice == nil else { return }
                await Task.yield()
                viewModel.refreshNotice = CelesTrakViewModel.previewRefreshLimitedNotice
            }
    }
}

private extension CelesTrakViewModel {
    /// Shared sample records used by preview states.
    static var previewSampleTLEs: [TLE] {
        [
            TLE(name: "BLUEBIRD-1", line1: "1 00001U 98067A   20344.12345678  .00001234  00000-0  10270-3 0  9991", line2: "2 00001  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456"),
            TLE(name: "BLUEBIRD-2", line1: "1 00002U 98067A   20344.22345678  .00001234  00000-0  10270-3 0  9992", line2: "2 00002  51.6431  21.2862 0007417  92.3844  10.1234 15.48912345123456")
        ]
    }

    /// Shows the common "loaded" path so contributors can tune card layout quickly.
    static func previewLoadedModel() -> CelesTrakViewModel {
        let viewModel = CelesTrakViewModel(cooldownPersistence: .disabled)
        viewModel.tles = previewSampleTLEs
        viewModel.state = .loaded(previewSampleTLEs)
        viewModel.lastFetchedAt = Date()
        viewModel.dataAge = 120
        return viewModel
    }

    /// Shows loading UI without requiring any network calls in previews.
    static func previewLoadingModel() -> CelesTrakViewModel {
        let viewModel = CelesTrakViewModel(cooldownPersistence: .disabled)
        viewModel.state = .loading
        return viewModel
    }

    /// Shows error UI so message wrapping and red styling are easy to verify.
    static func previewErrorModel() -> CelesTrakViewModel {
        let viewModel = CelesTrakViewModel(cooldownPersistence: .disabled)
        viewModel.state = .error("Unable to fetch TLE data right now. Please try again in a moment.")
        return viewModel
    }

    /// Shared preview alert content so preview setups stay in sync.
    static var previewRefreshLimitedNotice: CelesTrakViewModel.RefreshNotice {
        let viewModel = previewLoadedModel()
        return viewModel.manualRefreshCooldownNotice(
            nextAllowedRefreshDate: Date().addingTimeInterval(14 * 60)
        )
    }
}
