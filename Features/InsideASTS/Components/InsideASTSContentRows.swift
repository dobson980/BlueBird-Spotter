//
//  InsideASTSContentRows.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import SwiftUI

/// Reusable row-level building blocks for Inside ASTS cards.
///
/// Why this exists:
/// - Multiple Inside ASTS cards share chips, bullet rows, process blocks, and links.
/// - Keeping these primitives centralized reduces duplication and visual drift.
///
/// What this does NOT do:
/// - It does not define section expansion rules.
/// - It does not own feature copy or section ordering.
struct InsideASTSMetricChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDInset(cornerRadius: 10)
    }
}

/// Bullet row style that keeps explanatory text easy to scan.
struct InsideASTSBulletRow: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.top, 6)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(colorScheme.readableSecondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Formats app-pipeline steps as compact cards.
struct InsideASTSProcessStepRow: View {
    let title: String
    let description: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(description)
                .font(.caption)
                .foregroundStyle(colorScheme.readableSecondaryTextColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDInset(cornerRadius: 10)
    }
}

/// Highlights the educational-use disclaimer in a style that matches the HUD card system.
struct InsideASTSEducationalUseNotice: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 20, height: 20)
                .background(BlueBirdHUDStyle.headerGradient, in: Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Educational Use")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(colorScheme.readableTertiaryTextColor)

                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colorScheme.readableSecondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDInset(cornerRadius: 10)
        .blueBirdHUDGlass(
            tint: Color(red: 0.04, green: 0.61, blue: 0.86).opacity(colorScheme == .dark ? 0.24 : 0.12),
            cornerRadius: 10
        )
    }
}

/// Link row with an external-link icon for visual clarity.
struct InsideASTSSourceLinkRow: View {
    let title: String
    let url: String

    var body: some View {
        if let safeURL = URL(string: url) {
            Link(destination: safeURL) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                    Text(title)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .blueBirdHUDInset(cornerRadius: 10)
                .blueBirdHUDGlass(
                    tint: Color(red: 0.03, green: 0.76, blue: 0.62).opacity(0.25),
                    cornerRadius: 10,
                    interactive: true
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Preview for validating shared Inside ASTS row components in one canvas.
#Preview("Rows") {
    InsideASTSContentRowsPreview()
        .padding()
        .background(Color.black)
}

private struct InsideASTSContentRowsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                InsideASTSMetricChip(title: "Coverage Vision", value: "Global")
                InsideASTSMetricChip(title: "MNO Agreements", value: "50+")
                InsideASTSMetricChip(title: "Subscriber Reach", value: "~3B")
            }

            InsideASTSBulletRow(text: "AST states it has agreements with 50+ mobile network operators.")

            InsideASTSProcessStepRow(
                title: "1) TLE ingestion and refresh",
                description: "The app fetches AST-related TLEs from CelesTrak and refreshes stale data."
            )

            InsideASTSEducationalUseNotice(
                text: "This app is for education and analysis and does not guarantee exact precision."
            )

            InsideASTSSourceLinkRow(
                title: "AST SpaceMobile FAQ",
                url: "https://ast-science.com/faq/"
            )
        }
    }
}

private extension ColorScheme {
    /// Higher-contrast secondary text improves readability on bright glass in light mode.
    var readableSecondaryTextColor: Color {
        self == .dark ? .secondary : Color.black.opacity(0.78)
    }

    /// Tertiary text stays de-emphasized without becoming washed out in light mode.
    var readableTertiaryTextColor: Color {
        self == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62)
    }
}
