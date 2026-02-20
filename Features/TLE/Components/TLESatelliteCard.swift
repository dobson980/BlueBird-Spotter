//
//  TLESatelliteCard.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import SwiftUI

/// Reusable HUD-style card that displays one TLE entry.
///
/// Why this exists:
/// - `TLEListView` should focus on loading state and section orchestration.
/// - The row rendering is large and benefits from isolated layout ownership.
///
/// What this does not do:
/// - It does not own tap behavior or navigation.
/// - It does not fetch or parse TLEs.
struct TLESatelliteCard: View {
    let tle: TLE

    /// Tracks light/dark mode for adaptive divider styling.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let descriptor = SatelliteProgramCatalog.descriptor(forTLEName: tle.name, line1: tle.line1)
        let noradID = SatelliteIDParser.parseNoradId(line1: tle.line1)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)

                    if let catalogName = tle.name, descriptor.displayName != catalogName {
                        Text(catalogName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }

                Spacer(minLength: 0)

                if let noradID {
                    capsuleChip(icon: "number", text: "\(noradID)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(BlueBirdHUDStyle.headerGradient)

            Divider()
                .overlay(.white.opacity(colorScheme == .dark ? 0.14 : 0.22))

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    tleLine(tle.line1)
                    tleLine(tle.line2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .blueBirdHUDInset(cornerRadius: 10)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDCard(cornerRadius: 16, tint: Color(red: 0.04, green: 0.61, blue: 0.86))
    }

    /// Keeps fixed-width TLE strings readable without forcing wider cards.
    private func tleLine(_ line: String) -> some View {
        // Horizontal scrolling keeps full TLE lines accessible on narrow devices.
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
}

/// Preview for validating card typography and horizontal line scrolling.
#Preview("Default") {
    TLESatelliteCard(tle: .preview)
        .padding()
        .background(Color.black)
}

/// Preview for checking contrast and divider behavior in dark appearance.
#Preview("Dark") {
    TLESatelliteCard(tle: .preview)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

private extension TLE {
    /// Shared sample entry so card previews stay deterministic.
    static var preview: TLE {
        TLE(
            name: "BLUEWALKER 3",
            line1: "1 53807U 22094A   26049.33159722  .00001214  00000-0  11117-3 0  9990",
            line2: "2 53807  53.0491 190.1207 0001653 126.1334 233.9839 15.06331429189741"
        )
    }
}
