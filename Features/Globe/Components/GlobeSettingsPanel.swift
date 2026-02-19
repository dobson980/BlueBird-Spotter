//
//  GlobeSettingsPanel.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/18/26.
//

import SwiftUI

/// Modern settings HUD for the globe screen.
///
/// Why this exists:
/// - The globe settings should match the same visual language as the selected-satellite context card.
/// - Keeping this panel separate from `GlobeView` prevents the parent screen from becoming a mixed-responsibility file.
///
/// What this does NOT do:
/// - It does not own persistence policy; it only edits values exposed through bindings.
/// - It does not coordinate tracking or camera behavior.
struct GlobeSettingsPanel: View {
    @Binding var appAppearanceMode: AppAppearanceMode
    @Binding var directionalLightEnabled: Bool
    @Binding var coverageMode: CoverageFootprintMode
    @Binding var orbitPathMode: OrbitPathMode
    @Binding var orbitPathThickness: Double
    @Binding var orbitPathColorId: String

    /// Adaptive contrast keeps card edges readable over bright Earth textures.
    @Environment(\.colorScheme) private var colorScheme

    /// Tuned constants that keep spacing and scale consistent across sections.
    private enum Layout {
        static let panelCornerRadius: CGFloat = 20
        static let sectionCornerRadius: CGFloat = 14
        static let maxPanelWidth: CGFloat = 292
        static let sectionSpacing: CGFloat = 12
        static let outerPadding: CGFloat = 12
        static let sectionPadding: CGFloat = 12
    }

    /// Current color drives slider tint and selected-swatch emphasis.
    private var selectedOrbitColorOption: OrbitPathColorOption {
        OrbitPathColorOption.options.first { $0.id == orbitPathColorId } ?? OrbitPathColorOption.defaultOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(.white.opacity(colorScheme == .dark ? 0.14 : 0.22))

            settingsSectionStack
                .padding(Layout.outerPadding)
        }
        .frame(maxWidth: Layout.maxPanelWidth, alignment: .leading)
        .background { panelBackground }
        .overlay { panelBorder }
        .clipShape(RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.2), radius: 16, x: 0, y: 8)
    }

    /// Bright header mirrors the satellite context card to unify the globe HUD family.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))

            Text("Globe Settings")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.sectionPadding)
        .padding(.vertical, 12)
        .background(headerGradient)
    }

    /// Groups section cards so Liquid Glass can blend neighboring surfaces cleanly.
    @ViewBuilder
    private var settingsSectionStack: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: Layout.sectionSpacing) {
                sectionsContent
            }
        } else {
            sectionsContent
        }
    }

    /// Main settings controls keep existing behavior while upgrading visual hierarchy.
    private var sectionsContent: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            sectionCard(
                icon: "circle.lefthalf.filled",
                title: "Appearance",
                tint: Color(red: 0.46, green: 0.73, blue: 0.96)
            ) {
                Picker("Appearance", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            sectionCard(
                icon: "sun.max",
                title: "Lighting",
                tint: Color(red: 0.97, green: 0.78, blue: 0.24)
            ) {
                Toggle("Sunlight (Real-Time)", isOn: $directionalLightEnabled)
            }

            sectionCard(
                icon: "dot.radiowaves.left.and.right",
                title: "Coverage Footprints",
                tint: Color(red: 0.07, green: 0.72, blue: 0.91)
            ) {
                Picker("Coverage Footprints", selection: $coverageMode) {
                    ForEach(CoverageFootprintMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            sectionCard(
                icon: "point.3.filled.connected.trianglepath.dotted",
                title: "Orbit Paths",
                tint: Color(red: 0.03, green: 0.76, blue: 0.62)
            ) {
                Picker("Orbit Paths", selection: $orbitPathMode) {
                    ForEach(OrbitPathMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Path Thickness")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        // A fixed-width numeric readout makes small step changes easy to spot.
                        Text(orbitPathThickness.formatted(.number.precision(.fractionLength(3))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $orbitPathThickness, in: 0.001...0.02, step: 0.001)
                        .tint(selectedOrbitColorOption.color)
                }

                colorSwatchRow
            }
        }
    }

    /// Builds a reusable card shell so all settings sections feel like one system.
    private func sectionCard<Content: View>(
        icon: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            content()
        }
        .padding(Layout.sectionPadding)
        .background { sectionBackground }
        .overlay { sectionBorder }
        .clipShape(RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous))
        .globePanelGlass(
            tint: tint.opacity(colorScheme == .dark ? 0.24 : 0.14),
            cornerRadius: Layout.sectionCornerRadius
        )
    }

    /// Color swatches stay visual-first for fast orbit style changes.
    private var colorSwatchRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Path Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(OrbitPathColorOption.options) { option in
                    Button {
                        orbitPathColorId = option.id
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(option.color)
                            .frame(width: 26, height: 26)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(option.id == orbitPathColorId ? Color.white : Color.white.opacity(0.22), lineWidth: 1)
                            }
                            .overlay {
                                if option.id == orbitPathColorId {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .globePanelGlass(
                        tint: option.color.opacity(option.id == orbitPathColorId ? 0.55 : 0.32),
                        cornerRadius: 6,
                        interactive: true
                    )
                    .accessibilityLabel(option.name)
                    .accessibilityValue(option.id == orbitPathColorId ? "Selected" : "Not selected")
                }
            }
        }
    }

    /// Consistent gradient creates the same strong anchor used by the selection panel.
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

    /// Panel-level material blend keeps controls readable while preserving globe context.
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous)
        return shape
            .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.74))
            .background(.ultraThinMaterial, in: shape)
    }

    /// Subtle edge treatment avoids low-contrast card boundaries over bright textures.
    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.34), .white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    /// Section cards use a lighter fill so segmented controls do not blend into the parent card.
    private var sectionBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous)
        return shape
            .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.14))
            .background(.ultraThinMaterial, in: shape)
    }

    /// Very light section border preserves hierarchy without adding harsh outlines.
    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.16), lineWidth: 1)
    }
}

private extension View {
    /// Applies Liquid Glass when available and keeps a no-op fallback for non-26 runtimes.
    @ViewBuilder
    func globePanelGlass(tint: Color, cornerRadius: CGFloat, interactive: Bool = false) -> some View {
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
