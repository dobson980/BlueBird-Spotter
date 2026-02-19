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
    /// Shared sizing keeps compact telemetry labels and values vertically consistent.
    private let compactMetricHeaderHeight: CGFloat = 15
    /// Fixed line height avoids visual jitter between one-line and two-line segments.
    private let compactMetricValueLineHeight: CGFloat = 19

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

    /// Formats signed degrees for explicit Lat/Lon rows in compact telemetry.
    private func formatSignedDegrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "°"
    }

    /// Rounds kilometers for a compact UI-friendly readout.
    private func formatKilometers(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Formats the satellite speed (magnitude of the velocity vector) as a numeric km/h value.
    private func formatVelocity(_ velocityKmPerSec: SIMD3<Double>?) -> String {
        guard let velocityKmPerSec else { return "—" }
        let speedKmPerSec = (velocityKmPerSec.x * velocityKmPerSec.x
                             + velocityKmPerSec.y * velocityKmPerSec.y
                             + velocityKmPerSec.z * velocityKmPerSec.z).squareRoot()
        // Convert km/s to km/h for display (matches satellitetracker3d.com).
        let speedKmPerHour = speedKmPerSec * 3600
        return String(format: "%.0f", speedKmPerHour)
    }

    /// Builds a card-style row that highlights live tracking values with overlay-inspired telemetry.
    private func trackingRow(_ tracked: TrackedSatellite) -> some View {
        let descriptor = SatelliteProgramCatalog.descriptor(for: tracked.satellite)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)

                    if descriptor.displayName != tracked.satellite.name {
                        Text(tracked.satellite.name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }

                Spacer(minLength: 0)

                capsuleChip(icon: "number", text: "\(tracked.satellite.id)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(BlueBirdHUDStyle.headerGradient)

            Divider()
                .overlay(.white.opacity(colorScheme == .dark ? 0.14 : 0.22))

            trackingTelemetry(for: tracked)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDCard(cornerRadius: 16, tint: Color(red: 0.04, green: 0.61, blue: 0.86))
    }

    /// Uses compact telemetry that gracefully reflows for narrow widths.
    private func trackingTelemetry(for tracked: TrackedSatellite) -> some View {
        ViewThatFits(in: .horizontal) {
            compactTelemetryThreeColumn(tracked: tracked)
            compactTelemetryDenseThreeColumn(tracked: tracked)
        }
    }

    /// Preferred layout keeps POS, VEL, and ALT on one line when width allows.
    private func compactTelemetryThreeColumn(tracked: TrackedSatellite) -> some View {
        HStack(alignment: .top, spacing: 0) {
            compactPositionSegment(
                latitude: tracked.position.latitudeDegrees,
                longitude: tracked.position.longitudeDegrees
            )
            compactSegmentDivider
            compactTelemetrySegment(
                icon: "speedometer",
                title: "Vel km/h",
                value: formatVelocity(tracked.position.velocityKmPerSec)
            )
            compactSegmentDivider
            compactTelemetrySegment(
                icon: "arrow.up.and.down",
                title: "Alt km",
                value: formatKilometers(tracked.position.altitudeKm)
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDInset(cornerRadius: 10)
    }

    /// Dense fallback keeps all telemetry on one row to avoid tall cards on narrow widths.
    private func compactTelemetryDenseThreeColumn(tracked: TrackedSatellite) -> some View {
        HStack(alignment: .top, spacing: 0) {
            compactPositionSegment(
                latitude: tracked.position.latitudeDegrees,
                longitude: tracked.position.longitudeDegrees,
                isDense: true
            )
            compactSegmentDivider
            compactTelemetrySegment(
                icon: "speedometer",
                title: "Vel",
                value: formatVelocity(tracked.position.velocityKmPerSec)
            )
            compactSegmentDivider
            compactTelemetrySegment(
                icon: "arrow.up.and.down",
                title: "Alt",
                value: formatKilometers(tracked.position.altitudeKm)
            )
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDInset(cornerRadius: 10)
    }

    /// Converts latitude/longitude into a compact cardinal format like N 44.7°.
    private func compactCoordinate(_ value: Double, isLatitude: Bool) -> String {
        let direction: String
        if isLatitude {
            direction = value < 0 ? "S" : "N"
        } else {
            direction = value < 0 ? "W" : "E"
        }
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(1)))
        return "\(direction) \(magnitude)°"
    }

    /// Position segment keeps explicit latitude/longitude rows for clarity.
    private func compactPositionSegment(latitude: Double, longitude: Double, isDense: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            compactSegmentHeader(icon: "location.fill", title: "Pos")

            Group {
                if isDense {
                    // Dense mode prioritizes compact cardinal coordinates to stay on one line.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            Text(compactCoordinate(latitude, isLatitude: true))
                            Text(compactCoordinate(longitude, isLatitude: false))
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                        Text("\(formatSignedDegrees(latitude))  \(formatSignedDegrees(longitude))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    // Prefer fully labeled coordinates, then fall back to a denser line on narrow widths.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            Text("Lat \(formatSignedDegrees(latitude))")
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("Lon \(formatSignedDegrees(longitude))")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                        Text("\(formatSignedDegrees(latitude))  \(formatSignedDegrees(longitude))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(height: compactMetricValueLineHeight, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isDense ? 5 : 6)
        // Keep segment heights consistent so header rows align cleanly.
        .frame(minHeight: isDense ? 42 : 44, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Generic value segment used by velocity and altitude columns.
    private func compactTelemetrySegment(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            compactSegmentHeader(icon: icon, title: title)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: compactMetricValueLineHeight, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // Keep segment heights consistent so header rows align cleanly.
        .frame(minHeight: 42, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shared segment header keeps icon and label consistent across compact tiles.
    private func compactSegmentHeader(icon: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 13, height: 13, alignment: .center)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(height: compactMetricHeaderHeight, alignment: .leading)
    }

    /// Slim divider keeps segments visually separated without card-heavy chrome.
    private var compactSegmentDivider: some View {
        Rectangle()
            .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.18))
            .frame(width: 1)
            .padding(.vertical, 4)
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

    /// Capsule badge used in row-header metadata.
    private func capsuleChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.16), in: Capsule())
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
                            trackingRow(tracked)
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

/// Category section model for the tracking list.
private struct TrackingSection: Identifiable {
    let category: SatelliteProgramCategory
    let satellites: [TrackedSatellite]
    var id: String { category.label }
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
