//
//  InsideASTSFeatureImage.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/19/26.
//

import SwiftUI
import UIKit

/// Shared image treatment for Inside ASTS cards.
///
/// Why this exists:
/// - Hero and expandable sections should render visuals with one consistent frame,
///   border, and fallback behavior.
/// - Keeping this logic in one place prevents duplicated image checks in views.
///
/// What this does NOT do:
/// - It does not decide which content sections are expanded.
/// - It does not own copy or section-level layout.
struct InsideASTSFeatureImage: View {
    let assetName: String
    let fallbackIcon: String
    let fallbackTitle: String

    /// Adaptive border contrast keeps image edges visible in both appearance modes.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.cyan.opacity(0.18), Color.blue.opacity(0.12), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 6) {
                    Image(systemName: fallbackIcon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(fallbackTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.2), lineWidth: 1)
        )
    }
}

/// Preview for validating the fallback treatment when an asset is missing.
#Preview("Fallback") {
    InsideASTSFeatureImage(
        assetName: "missing-inside-asts-image",
        fallbackIcon: "photo",
        fallbackTitle: "Preview Placeholder"
    )
    .padding()
    .background(Color.black)
}
