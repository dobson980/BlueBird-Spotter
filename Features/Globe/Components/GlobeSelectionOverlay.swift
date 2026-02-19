//
//  GlobeSelectionOverlay.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/6/26.
//

import SwiftUI

/// Modern HUD-style overlay for the currently selected satellite.
///
/// Why this exists:
/// - The selected-satellite pane should be scannable while the globe continues
///   updating behind it.
/// - The layout emphasizes the values users care about most in live tracking:
///   name, position, velocity, and altitude.
///
/// What this does NOT do:
/// - It does not expose raw TLE status controls or dismiss actions.
/// - It does not claim mission-operations precision for coverage.
struct GlobeSelectionOverlay: View {
    let trackedSatellite: TrackedSatellite

    /// Adapts panel contrast so text remains readable over the globe.
    @Environment(\.colorScheme) private var colorScheme

    /// Visual constants used by the HUD layout.
    private enum OverlayLayout {
        static let cornerRadius: CGFloat = 20
        static let maxPanelWidth: CGFloat = 292
        static let overallScale: CGFloat = 0.7
        static let altitudeReferenceMinKm: Double = 400
        static let altitudeReferenceMaxKm: Double = 700
    }

    /// Program metadata drives display naming and educational category labels.
    private var programDescriptor: SatelliteProgramDescriptor {
        SatelliteProgramCatalog.descriptor(for: trackedSatellite.satellite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroHeader

            Divider()
                .overlay(.white.opacity(colorScheme == .dark ? 0.14 : 0.22))

            telemetrySection
            footerSection
        }
        .frame(maxWidth: OverlayLayout.maxPanelWidth, alignment: .leading)
        .background { panelBackground }
        .overlay { panelBorder }
        .clipShape(RoundedRectangle(cornerRadius: OverlayLayout.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 14, x: 0, y: 8)
        // Proportionally scale the full card to reduce visual footprint
        // without retuning every spacing and font value independently.
        .scaleEffect(OverlayLayout.overallScale, anchor: .topLeading)
        // Smooth interpolation helps one-second telemetry updates feel continuous.
        .animation(.smooth(duration: 0.45), value: trackedSatellite.position.altitudeKm)
        .animation(.smooth(duration: 0.45), value: trackedSatellite.position.latitudeDegrees)
        .animation(.smooth(duration: 0.45), value: trackedSatellite.position.longitudeDegrees)
    }

    /// High-contrast top band with identity and key context chips.
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))

                VStack(alignment: .leading, spacing: 4) {
                    Text(programDescriptor.displayName)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if programDescriptor.displayName != trackedSatellite.satellite.name {
                        Text(trackedSatellite.satellite.name)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 8) {
                chip(icon: "square.stack.3d.up.fill", text: programDescriptor.category.label)
                chip(icon: "number", text: "\(trackedSatellite.satellite.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(headerGradient)
    }

    /// Primary telemetry section with position, velocity, and altitude.
    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            telemetryRow(
                icon: "location.fill",
                title: "Position",
                value: "\(formatLatitude(trackedSatellite.position.latitudeDegrees))   \(formatLongitude(trackedSatellite.position.longitudeDegrees))"
            )

            telemetryRow(
                icon: "speedometer",
                title: "Velocity",
                value: formatVelocity(trackedSatellite.position.velocityKmPerSec)
            )

            altitudeCard

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Coverage")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(coverageLabel)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// Minimal footer keeps a single live status without extra telemetry clutter.
    private var footerSection: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    /// Distinct altitude panel with a compact progress bar.
    private var altitudeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Altitude")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formatKilometers(trackedSatellite.position.altitudeKm))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("km")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(colorScheme == .dark ? 0.14 : 0.18))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.11, green: 0.82, blue: 0.63), Color(red: 0.07, green: 0.72, blue: 0.91)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * altitudeProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(OverlayLayout.altitudeReferenceMinKm)) km")
                Spacer(minLength: 0)
                Text("\(Int(OverlayLayout.altitudeReferenceMaxKm)) km")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(colorScheme == .dark ? 0.05 : 0.12))
        )
    }

    /// Reusable stat row layout for position/velocity.
    private func telemetryRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    /// Capsule badge used for category and NORAD quick context.
    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.16), in: Capsule())
    }

    /// Gradient top band gives the panel a stronger visual anchor.
    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.76, blue: 0.62),
                Color(red: 0.04, green: 0.61, blue: 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Main card fill layered over material to preserve readability.
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: OverlayLayout.cornerRadius, style: .continuous)
        return shape
            .fill(colorScheme == .dark ? Color.black.opacity(0.52) : Color.white.opacity(0.76))
            .background(.ultraThinMaterial, in: shape)
    }

    /// Subtle border keeps the card edge legible over bright Earth textures.
    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: OverlayLayout.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.35), .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    /// Normalized progress for the altitude reference bar.
    private var altitudeProgress: CGFloat {
        let minKm = OverlayLayout.altitudeReferenceMinKm
        let maxKm = OverlayLayout.altitudeReferenceMaxKm
        guard maxKm > minKm else { return 0 }
        let normalized = (trackedSatellite.position.altitudeKm - minKm) / (maxKm - minKm)
        return CGFloat(min(max(normalized, 0), 1))
    }

    /// Formats latitude with hemisphere prefix for quick visual scanning.
    private func formatLatitude(_ value: Double) -> String {
        let hemisphere = value >= 0 ? "N" : "S"
        return "\(hemisphere) \(abs(value).formatted(.number.precision(.fractionLength(2))))°"
    }

    /// Formats longitude with hemisphere prefix for quick visual scanning.
    private func formatLongitude(_ value: Double) -> String {
        let hemisphere = value >= 0 ? "E" : "W"
        return "\(hemisphere) \(abs(value).formatted(.number.precision(.fractionLength(2))))°"
    }

    /// Rounds kilometers for a compact overlay readout.
    private func formatKilometers(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// Formats the satellite speed (magnitude of the velocity vector) in km/h.
    private func formatVelocity(_ velocityKmPerSec: SIMD3<Double>?) -> String {
        guard let velocityKmPerSec else { return "—" }
        let speedKmPerSec = (velocityKmPerSec.x * velocityKmPerSec.x
                             + velocityKmPerSec.y * velocityKmPerSec.y
                             + velocityKmPerSec.z * velocityKmPerSec.z).squareRoot()
        // Convert km/s to km/h for display so values are intuitive for non-experts.
        let speedKmPerHour = speedKmPerSec * 3600
        return "\(speedKmPerHour.formatted(.number.precision(.fractionLength(0)))) km/h"
    }

    /// Compact educational estimate shown in the selected-satellite info panel.
    private var coverageLabel: String {
        SatelliteProgramCatalog.estimatedCoverageLabel(
            for: trackedSatellite.satellite,
            altitudeKm: trackedSatellite.position.altitudeKm
        )
        .replacingOccurrences(of: " (estimate)", with: "")
    }
}

/// Preview for validating the selection overlay with full telemetry values.
#Preview("With Velocity") {
    GlobeSelectionOverlay(trackedSatellite: GlobeSelectionOverlayPreviewFactory.withVelocity)
        .padding()
}

/// Preview for validating the velocity placeholder when speed is unavailable.
#Preview("No Velocity") {
    GlobeSelectionOverlay(trackedSatellite: GlobeSelectionOverlayPreviewFactory.withoutVelocity)
        .padding()
}

/// Preview fixtures for `GlobeSelectionOverlay`.
private enum GlobeSelectionOverlayPreviewFactory {
    /// Sample satellite containing a velocity vector.
    static let withVelocity = TrackedSatellite(
        satellite: Satellite(
            id: 45854,
            name: "BLUEBIRD-1",
            tleLine1: "1 45854U 20008A   26036.22192385  .00005457  00000+0  43089-3 0  9994",
            tleLine2: "2 45854  53.0544 292.8396 0001647  89.3122 270.8203 15.06378191327752",
            epoch: Date()
        ),
        position: SatellitePosition(
            timestamp: Date(),
            latitudeDegrees: 35.72,
            longitudeDegrees: -95.44,
            altitudeKm: 547.9,
            velocityKmPerSec: SIMD3(6.8, 2.0, -0.1)
        )
    )

    /// Sample satellite with missing velocity to exercise placeholder UI.
    static let withoutVelocity = TrackedSatellite(
        satellite: Satellite(
            id: 45955,
            name: "BLUEBIRD-2",
            tleLine1: "1 45955U 20040A   26036.13484363  .00004642  00000+0  37482-3 0  9998",
            tleLine2: "2 45955  53.0539 293.2265 0001579  90.5216 269.6102 15.06348287306616",
            epoch: Date()
        ),
        position: SatellitePosition(
            timestamp: Date(),
            latitudeDegrees: 14.12,
            longitudeDegrees: -28.65,
            altitudeKm: 546.3,
            velocityKmPerSec: nil
        )
    )
}
