//
//  InsideASTSExpandableCard.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import SwiftUI

/// Reusable expandable card shell for Inside ASTS information sections.
///
/// Why this exists:
/// - Multiple sections share the same header chrome, expand/collapse behavior,
///   and optional feature image slot.
/// - A dedicated component keeps the main screen focused on content composition.
///
/// What this does NOT do:
/// - It does not own expansion state storage.
/// - It does not decide the order or text of feature sections.
struct InsideASTSExpandableCard<Content: View>: View {
    let title: String
    let subtitle: String
    let iconName: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let assetName: String?
    let fallbackTitle: String
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onToggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(BlueBirdHUDStyle.headerGradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            Divider()
                .overlay(.white.opacity(colorScheme == .dark ? 0.14 : 0.22))

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let assetName {
                        InsideASTSFeatureImage(
                            assetName: assetName,
                            fallbackIcon: iconName,
                            fallbackTitle: fallbackTitle
                        )
                    }

                    content()
                }
                .padding(12)
                // Keep expansion anchored below the header so content does not sweep across it.
                .transition(.opacity)
            }
        }
        .blueBirdHUDCard(cornerRadius: 16, tint: Color(red: 0.04, green: 0.61, blue: 0.86))
    }
}

/// Preview for validating expandable card behavior with feature image fallback.
#Preview("Interactive") {
    InsideASTSExpandableCardPreviewHost()
        .padding()
        .background(Color.black)
}

private struct InsideASTSExpandableCardPreviewHost: View {
    /// Local preview state mirrors how the parent screen manages expansion.
    @State private var isExpanded = true

    var body: some View {
        InsideASTSExpandableCard(
            title: "How the App Works",
            subtitle: "From TLEs to live globe rendering",
            iconName: "point.3.connected.trianglepath.dotted",
            isExpanded: isExpanded,
            onToggle: { isExpanded.toggle() },
            assetName: "missing-inside-asts-image",
            fallbackTitle: "Preview Placeholder"
        ) {
            InsideASTSProcessStepRow(
                title: "1) TLE ingestion and refresh",
                description: "The app fetches AST-related TLEs and updates stale data."
            )
        }
    }
}
