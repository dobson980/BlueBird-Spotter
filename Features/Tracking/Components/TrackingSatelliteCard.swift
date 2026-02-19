//
//  TrackingSatelliteCard.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import SwiftUI

/// Reusable HUD-style card that displays one tracked satellite's telemetry.
///
/// Why this exists:
/// - `TrackingView` should focus on list orchestration and section behavior.
/// - Row rendering is large enough to deserve a dedicated, testable UI unit.
///
/// What this does not do:
/// - It does not own navigation or selection behavior.
/// - It does not fetch or compute tracking data.
struct TrackingSatelliteCard: View {
    let tracked: TrackedSatellite

    /// Tracks light/dark mode for adaptive divider styling.
    @Environment(\.colorScheme) private var colorScheme
    /// Shared sizing keeps compact telemetry labels and values vertically consistent.
    private let compactMetricHeaderHeight: CGFloat = 15
    /// Fixed line height avoids visual jitter between one-line and two-line segments.
    private let compactMetricValueLineHeight: CGFloat = 19

    var body: some View {
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

            trackingTelemetry
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDCard(cornerRadius: 16, tint: Color(red: 0.04, green: 0.61, blue: 0.86))
    }

    /// Uses compact telemetry that gracefully reflows for narrow widths.
    private var trackingTelemetry: some View {
        ViewThatFits(in: .horizontal) {
            compactTelemetryThreeColumn
            compactTelemetryDenseThreeColumn
        }
    }

    /// Preferred layout keeps POS, VEL, and ALT on one line when width allows.
    private var compactTelemetryThreeColumn: some View {
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
    private var compactTelemetryDenseThreeColumn: some View {
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

    /// Formats signed degrees for explicit Lat/Lon rows in compact telemetry.
    private func formatSignedDegrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "°"
    }

    /// Rounds kilometers for a compact UI-friendly readout.
    private func formatKilometers(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Formats the satellite speed (magnitude of velocity) as km/h.
    private func formatVelocity(_ velocityKmPerSec: SIMD3<Double>?) -> String {
        guard let velocityKmPerSec else { return "—" }
        let speedKmPerSec = (velocityKmPerSec.x * velocityKmPerSec.x
                             + velocityKmPerSec.y * velocityKmPerSec.y
                             + velocityKmPerSec.z * velocityKmPerSec.z).squareRoot()
        // Convert km/s to km/h for display (matches satellitetracker3d.com).
        let speedKmPerHour = speedKmPerSec * 3600
        return String(format: "%.0f", speedKmPerHour)
    }

    /// Converts latitude/longitude into compact cardinal text like N 44.7°.
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
}
