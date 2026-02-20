//
//  BlueBirdHUDStyle.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/18/26.
//

import SwiftUI

/// Shared style tokens and modifiers for the app's HUD-like glass surfaces.
///
/// Why this exists:
/// - TLE, Tracking, Information, and Globe overlays should look like one cohesive system.
/// - Centralizing these values keeps color, border, and corner-radius policy consistent.
///
/// What this does NOT do:
/// - It does not own layout or data formatting decisions.
/// - It does not force animation behavior for individual feature views.
enum BlueBirdHUDStyle {
    /// Default corner radius for primary cards.
    static let cardCornerRadius: CGFloat = 16
    /// Slightly tighter radius for inset chips and content trays.
    static let insetCornerRadius: CGFloat = 12

    /// Shared gradient used for top labels and hero header bands.
    static let headerGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.76, blue: 0.62),
            Color(red: 0.04, green: 0.61, blue: 0.86)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Applies the primary HUD card surface treatment used across tabs.
private struct BlueBirdHUDCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.74))
                    .background(.ultraThinMaterial, in: shape)
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.34), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(shape)
            .blueBirdHUDGlass(
                tint: tint.opacity(colorScheme == .dark ? 0.24 : 0.14),
                cornerRadius: cornerRadius
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 14, x: 0, y: 8)
    }
}

/// Applies the secondary inset surface used inside primary cards.
private struct BlueBirdHUDInsetModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.14))
                    .background(.ultraThinMaterial, in: shape)
            }
            .overlay {
                shape
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.16), lineWidth: 1)
            }
            .clipShape(shape)
    }
}

extension View {
    /// Wraps content in the shared primary HUD surface.
    func blueBirdHUDCard(cornerRadius: CGFloat = BlueBirdHUDStyle.cardCornerRadius, tint: Color = .clear) -> some View {
        modifier(BlueBirdHUDCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Wraps content in the shared secondary inset surface.
    func blueBirdHUDInset(cornerRadius: CGFloat = BlueBirdHUDStyle.insetCornerRadius) -> some View {
        modifier(BlueBirdHUDInsetModifier(cornerRadius: cornerRadius))
    }

    /// Applies Liquid Glass where available and keeps a no-op fallback elsewhere.
    @ViewBuilder
    func blueBirdHUDGlass(tint: Color, cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
        }
    }
}

/// Preview host for validating shared HUD card and inset style tokens.
private struct BlueBirdHUDStylePreviewHost: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text("BlueBird HUD Style")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(BlueBirdHUDStyle.headerGradient)

            VStack(alignment: .leading, spacing: 6) {
                Text("Inset Surface")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Shared style preview for card and inset appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blueBirdHUDInset(cornerRadius: 10)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .blueBirdHUDCard(cornerRadius: 16, tint: Color(red: 0.04, green: 0.61, blue: 0.86))
        .padding()
        .background(Color.black)
    }
}

/// Preview for validating shared HUD style in dark appearance.
#Preview("HUD Style - Dark", traits: .sizeThatFitsLayout) {
    BlueBirdHUDStylePreviewHost()
        .preferredColorScheme(.dark)
}

/// Preview for validating shared HUD style in light appearance.
#Preview("HUD Style - Light", traits: .sizeThatFitsLayout) {
    BlueBirdHUDStylePreviewHost()
        .preferredColorScheme(.light)
}
