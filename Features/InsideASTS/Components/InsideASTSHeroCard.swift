//
//  InsideASTSHeroCard.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import SwiftUI

/// Top orientation card shown at the start of the Inside ASTS screen.
///
/// Why this exists:
/// - The hero card has a distinct but reusable structure that should stay separate
///   from section orchestration logic.
/// - Extracting it keeps `InsideASTSView` focused on high-level composition.
///
/// What this does NOT do:
/// - It does not manage section expansion state.
/// - It does not own long-form source bullets.
struct InsideASTSHeroCard: View {
    /// Intro copy that frames the purpose of the Inside ASTS page.
    let introText: String
    /// Footnote copy that timestamps the information snapshot.
    let snapshotText: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))

                Text("Inside ASTS")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(BlueBirdHUDStyle.headerGradient)

            Divider()
                .overlay(.white.opacity(colorScheme == .dark ? 0.14 : 0.22))

            VStack(alignment: .leading, spacing: 12) {
                InsideASTSFeatureImage(
                    assetName: "inside-asts-hero",
                    fallbackIcon: "globe.americas.fill",
                    fallbackTitle: "Add asset: inside-asts-hero"
                )

                Text(introText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    InsideASTSMetricChip(title: "Coverage Vision", value: "Global")
                    InsideASTSMetricChip(title: "MNO Agreements", value: "50+")
                    InsideASTSMetricChip(title: "Subscriber Reach", value: "~3B")
                }

                Text(snapshotText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .blueBirdHUDCard(cornerRadius: 16, tint: Color(red: 0.04, green: 0.61, blue: 0.86))
    }
}

/// Preview for validating hero card layout and metric chips.
#Preview("Hero") {
    InsideASTSHeroCard(
        introText: InsideASTSContent.heroIntro,
        snapshotText: InsideASTSContent.heroSnapshot
    )
    .padding()
    .background(Color.black)
}
