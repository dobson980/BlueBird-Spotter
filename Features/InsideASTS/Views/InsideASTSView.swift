//
//  InsideASTSView.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/5/26.
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
                        Text("Big-picture context, simplified")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Introduces the page with a concise orientation card.
    private var heroCard: some View {
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
        .background { primaryCardBackground(cornerRadius: 16) }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardBorderGradient, lineWidth: 1)
        )
        .shadow(color: cardShadowColor, radius: 4, x: 0, y: 2)
    }

    /// Summarizes AST SpaceMobile's mission, history, and commercial position.
    private var companyCard: some View {
        expandableCard(
            id: .company,
            title: "AST SpaceMobile: Mission and Momentum",
            subtitle: "A practical overview for non-technical readers",
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
            subtitle: "What changed, and why it matters",
            assetName: "inside-asts-bluebird",
            fallbackIcon: "satellite.fill",
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
            title: "How This App Works (High Level)",
            subtitle: "From TLE text to live globe visuals",
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
            subtitle: "Important context for interpreting what you see",
            assetName: "inside-asts-accuracy",
            fallbackIcon: "scope",
            fallbackTitle: "Add asset: inside-asts-accuracy"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(InsideASTSContent.accuracyBullets, id: \.self) { item in
                    bullet(item)
                }

                Text(InsideASTSContent.disclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background {
                        secondaryCardBackground(cornerRadius: 10)
                    }

                Text(InsideASTSContent.financeDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Provides direct links so readers can verify and keep learning.
    private var linksCard: some View {
        expandableCard(
            id: .links,
            title: "Primary Sources",
            subtitle: "Official references behind this page",
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
        VStack(alignment: .leading, spacing: 10) {
            if let assetName {
                featureImage(assetName: assetName, fallbackIcon: fallbackIcon, fallbackTitle: fallbackTitle)
            }

            DisclosureGroup(
                isExpanded: isExpandedBinding(for: id),
                content: {
                    content()
                        .padding(.top, 4)
                },
                label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .tint(.primary)
        }
        .padding(12)
        .background { primaryCardBackground(cornerRadius: 16) }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardBorderGradient, lineWidth: 1)
        )
        .shadow(color: cardShadowColor, radius: 4, x: 0, y: 2)
    }

    /// Binding helper that keeps the section expansion state in one place.
    private func isExpandedBinding(for id: SectionID) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(id)
                } else {
                    expandedSections.remove(id)
                }
            }
        )
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
        .background { secondaryCardBackground(cornerRadius: 10) }
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { secondaryCardBackground(cornerRadius: 10) }
    }

    /// Link row with an external-link icon for visual clarity.
    private func sourceLink(_ title: String, url: String) -> some View {
        Group {
            if let safeURL = URL(string: url) {
                Link(destination: safeURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                        Text(title)
                    }
                    .font(.subheadline)
                }
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

    /// Primary card background with adaptive material for light/dark modes.
    @ViewBuilder
    private func primaryCardBackground(cornerRadius: CGFloat) -> some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.45))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.7))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Secondary inset background for bullets and process steps.
    @ViewBuilder
    private func secondaryCardBackground(cornerRadius: CGFloat) -> some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.03))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.06))
        }
    }

    /// Soft neon border that is stronger in dark mode and subtle in light mode.
    private var cardBorderGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    .white.opacity(0.06),
                    .cyan.opacity(0.08),
                    .purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                .black.opacity(0.08),
                .cyan.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Restrained glow tint so cards look layered without overpowering text.
    private var cardShadowColor: Color {
        colorScheme == .dark ? .cyan.opacity(0.015) : .cyan.opacity(0.008)
    }
}

/// Preview for quickly validating the information tab layout.
#Preview {
    InsideASTSView()
}
