//
//  BlueBirdCollapsibleSectionHeader.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
//

import SwiftUI

/// Shared collapsible section header used by grouped HUD lists.
///
/// Why this exists:
/// - Tracking and TLE sections should share one visual language and interaction model.
/// - A minimal inline disclosure row keeps focus on satellite cards.
///
/// What this does NOT do:
/// - It does not own any row layout.
/// - It does not manage collapsed state storage.
struct BlueBirdCollapsibleSectionHeader: View {
    /// Visible section title (for example, "Block 1" or "BlueWalker").
    let title: String
    /// Number of rows inside this section.
    let count: Int
    /// Whether the section content is currently hidden.
    let isCollapsed: Bool
    /// Action called when the header is tapped.
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text(title.uppercased())
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .tracking(0.3)
                        .lineLimit(1)
                        // Keep headers readable against the always-dark space background in every appearance mode.
                        .foregroundStyle(.white.opacity(0.95))

                    countBadge

                    Spacer(minLength: 0)

                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                }

                Rectangle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.16 : 0.24))
                    .frame(height: 1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(title) section")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }

    /// Count badge is visually separated so it does not read like part of the title text.
    private var countBadge: some View {
        Text(satelliteCountLabel)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(colorScheme == .dark ? 0.26 : 0.34), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.16), lineWidth: 1)
            )
            .lineLimit(1)
    }

    /// Uses explicit wording so the count is read as a satellite total, not an identifier.
    private var satelliteCountLabel: String {
        count == 1 ? "1 satellite" : "\(count) satellites"
    }
}
