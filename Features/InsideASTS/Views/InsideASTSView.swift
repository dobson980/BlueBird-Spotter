//
//  InsideASTSView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/5/26.
//

import SwiftUI
import UIKit

/// Presents approachable context about AST SpaceMobile and this app's data pipeline.
///
/// The content is grouped into collapsible sections so readers can explore topics
/// without scrolling through one large wall of text.
struct InsideASTSView: View {
    /// Section ids track which cards are expanded for a cleaner reading experience.
    private enum SectionID: Hashable {
        case company
        case satellites
        case appFlow
        case accuracy
        case links
    }

    /// Theme adapts card backgrounds for dark and light modes.
    @Environment(\.colorScheme) private var colorScheme
    /// Start with top-level context expanded, then let users drill into details.
    @State private var expandedSections: Set<SectionID> = [.company, .appFlow]

    var body: some View {
        NavigationStack {
            ZStack {
                spaceBackground

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        heroCard
                        companyCard
                        satelliteCard
                        appFlowCard
                        accuracyCard
                        linksCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .safeAreaPadding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Inside ASTS")
                            .font(.headline.weight(.semibold))
                        Text("Company, satellites, and model")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Introduces the page with a concise orientation card.
    private var heroCard: some View {
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
                featureImage(assetName: "inside-asts-hero", fallbackIcon: "globe.americas.fill", fallbackTitle: "Add asset: inside-asts-hero")

                Text(InsideASTSContent.heroIntro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    metricChip(title: "Coverage Vision", value: "Global")
                    metricChip(title: "MNO Agreements", value: "50+")
                    metricChip(title: "Subscriber Reach", value: "~3B")
                }

                Text(InsideASTSContent.heroSnapshot)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .blueBirdHUDCard(cornerRadius: 16, tint: Color(red: 0.04, green: 0.61, blue: 0.86))
    }

    /// Summarizes AST SpaceMobile's mission, history, and commercial position.
    private var companyCard: some View {
        expandableCard(
            id: .company,
            title: "AST SpaceMobile: Mission and Momentum",
            subtitle: "Mission, scale, and rollout status",
            assetName: "inside-asts-company",
            fallbackIcon: "building.2.crop.circle",
            fallbackTitle: "Add asset: inside-asts-company"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(InsideASTSContent.companyBullets, id: \.self) { item in
                    bullet(item)
                }
            }
        }
    }

    /// Highlights what makes the BlueBird platform notable for readers and investors.
    private var satelliteCard: some View {
        expandableCard(
            id: .satellites,
            title: "BlueBird Satellites: Block 1 and Block 2",
            subtitle: "Generation differences and capacity impact",
            assetName: "inside-asts-bluebird",
            fallbackIcon: "antenna.radiowaves.left.and.right",
            fallbackTitle: "Add asset: inside-asts-bluebird"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Block 1 BlueBirds")
                    .font(.subheadline.weight(.semibold))
                ForEach(InsideASTSContent.block1Bullets, id: \.self) { item in
                    bullet(item)
                }

                Text("Block 2 / FM-1 Era")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                ForEach(InsideASTSContent.block2Bullets, id: \.self) { item in
                    bullet(item)
                }
            }
        }
    }

    /// Explains the app's data flow in approachable terms.
    private var appFlowCard: some View {
        expandableCard(
            id: .appFlow,
            title: "How the App Works",
            subtitle: "From TLEs to live globe rendering",
            assetName: "inside-asts-appflow",
            fallbackIcon: "point.3.connected.trianglepath.dotted",
            fallbackTitle: "Add asset: inside-asts-appflow"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(InsideASTSContent.processSteps) { step in
                    processStep(title: step.title, description: step.description)
                }
            }
        }
    }

    /// Sets expectations around approximations and intended use.
    private var accuracyCard: some View {
        expandableCard(
            id: .accuracy,
            title: "Accuracy, Limits, and Intent",
            subtitle: "What this model can and cannot provide",
            assetName: "inside-asts-accuracy",
            fallbackIcon: "scope",
            fallbackTitle: "Add asset: inside-asts-accuracy"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(InsideASTSContent.accuracyBullets, id: \.self) { item in
                    bullet(item)
                }

                educationalUseNotice(InsideASTSContent.disclaimer)

                Text(InsideASTSContent.financeDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(readableTertiaryTextColor)
            }
        }
    }

    /// Provides direct links so readers can verify and keep learning.
    private var linksCard: some View {
        expandableCard(
            id: .links,
            title: "Sources",
            subtitle: "Primary references",
            assetName: nil,
            fallbackIcon: "link",
            fallbackTitle: ""
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(InsideASTSContent.sourceReferences) { reference in
                    sourceLink(reference.title, url: reference.url)
                }
            }
        }
    }

    /// Builds a reusable expandable section card with optional visual.
    private func expandableCard<Content: View>(
        id: SectionID,
        title: String,
        subtitle: String,
        assetName: String?,
        fallbackIcon: String,
        fallbackTitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isExpanded = expandedSections.contains(id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleSection(id)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: fallbackIcon)
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
                        featureImage(assetName: assetName, fallbackIcon: fallbackIcon, fallbackTitle: fallbackTitle)
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

    /// Toggles one section with a smooth transition for readability.
    private func toggleSection(_ id: SectionID) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if expandedSections.contains(id) {
                expandedSections.remove(id)
            } else {
                expandedSections.insert(id)
            }
        }
    }

    /// Renders an image when available and a styled placeholder when missing.
    private func featureImage(assetName: String, fallbackIcon: String, fallbackTitle: String) -> some View {
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

    /// Small metric chip used in the hero section.
    private func metricChip(title: String, value: String) -> some View {
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

    /// Bullet row style that keeps explanatory text easy to scan.
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(readableSecondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Formats app-pipeline steps as compact cards.
    private func processStep(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(description)
                .font(.caption)
                .foregroundStyle(readableSecondaryTextColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueBirdHUDInset(cornerRadius: 10)
    }

    /// Highlights the educational-use disclaimer in a style that matches the HUD card system.
    private func educationalUseNotice(_ text: String) -> some View {
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
                    .foregroundStyle(readableTertiaryTextColor)

                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readableSecondaryTextColor)
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

    /// Link row with an external-link icon for visual clarity.
    private func sourceLink(_ title: String, url: String) -> some View {
        Group {
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

    /// Full-screen space backdrop shared across tabs.
    private var spaceBackground: some View {
        GeometryReader { geometry in
            Image("space")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.0))
        }
        .ignoresSafeArea()
    }

    /// Higher-contrast secondary text improves readability in light mode on bright glass cards.
    private var readableSecondaryTextColor: Color {
        colorScheme == .dark ? .secondary : Color.black.opacity(0.78)
    }

    /// Tertiary text is still de-emphasized but avoids becoming washed out in light mode.
    private var readableTertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62)
    }

}

/// Preview for quickly validating the information tab layout in dark mode.
#Preview("Dark") {
    InsideASTSView()
        .preferredColorScheme(.dark)
}

/// Preview for validating card contrast and readability in light mode.
#Preview("Light") {
    InsideASTSView()
        .preferredColorScheme(.light)
}
