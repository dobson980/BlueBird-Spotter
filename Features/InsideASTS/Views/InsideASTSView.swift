//
//  InsideASTSView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/5/26.
//

import SwiftUI

/// Presents approachable context about AST SpaceMobile and this app's data pipeline.
///
/// The content is grouped into collapsible sections so readers can explore topics
/// without scrolling through one large wall of text.
struct InsideASTSView: View {
    /// Section IDs track which cards are expanded for a cleaner reading experience.
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
        InsideASTSHeroCard(
            introText: InsideASTSContent.heroIntro,
            snapshotText: InsideASTSContent.heroSnapshot
        )
    }

    /// Summarizes AST SpaceMobile's mission, history, and commercial position.
    private var companyCard: some View {
        InsideASTSExpandableCard(
            title: "AST SpaceMobile: Mission and Momentum",
            subtitle: "Mission, scale, and rollout status",
            iconName: "building.2.crop.circle",
            isExpanded: isSectionExpanded(.company),
            onToggle: { toggleSection(.company) },
            assetName: "inside-asts-company",
            fallbackTitle: "Add asset: inside-asts-company"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(InsideASTSContent.companyBullets, id: \.self) { item in
                    InsideASTSBulletRow(text: item)
                }
            }
        }
    }

    /// Highlights what makes the BlueBird platform notable for readers and investors.
    private var satelliteCard: some View {
        InsideASTSExpandableCard(
            title: "BlueBird Satellites: Block 1 and Block 2",
            subtitle: "Generation differences and capacity impact",
            iconName: "antenna.radiowaves.left.and.right",
            isExpanded: isSectionExpanded(.satellites),
            onToggle: { toggleSection(.satellites) },
            assetName: "inside-asts-bluebird",
            fallbackTitle: "Add asset: inside-asts-bluebird"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Block 1 BlueBirds")
                    .font(.subheadline.weight(.semibold))
                ForEach(InsideASTSContent.block1Bullets, id: \.self) { item in
                    InsideASTSBulletRow(text: item)
                }

                Text("Block 2 / FM-1 Era")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                ForEach(InsideASTSContent.block2Bullets, id: \.self) { item in
                    InsideASTSBulletRow(text: item)
                }
            }
        }
    }

    /// Explains the app's data flow in approachable terms.
    private var appFlowCard: some View {
        InsideASTSExpandableCard(
            title: "How the App Works",
            subtitle: "From TLEs to live globe rendering",
            iconName: "point.3.connected.trianglepath.dotted",
            isExpanded: isSectionExpanded(.appFlow),
            onToggle: { toggleSection(.appFlow) },
            assetName: "inside-asts-appflow",
            fallbackTitle: "Add asset: inside-asts-appflow"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(InsideASTSContent.processSteps) { step in
                    InsideASTSProcessStepRow(
                        title: step.title,
                        description: step.description
                    )
                }
            }
        }
    }

    /// Sets expectations around approximations and intended use.
    private var accuracyCard: some View {
        InsideASTSExpandableCard(
            title: "Accuracy, Limits, and Intent",
            subtitle: "What this model can and cannot provide",
            iconName: "scope",
            isExpanded: isSectionExpanded(.accuracy),
            onToggle: { toggleSection(.accuracy) },
            assetName: "inside-asts-accuracy",
            fallbackTitle: "Add asset: inside-asts-accuracy"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(InsideASTSContent.accuracyBullets, id: \.self) { item in
                    InsideASTSBulletRow(text: item)
                }

                InsideASTSEducationalUseNotice(text: InsideASTSContent.disclaimer)

                Text(InsideASTSContent.financeDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(readableTertiaryTextColor)
            }
        }
    }

    /// Provides direct links so readers can verify and keep learning.
    private var linksCard: some View {
        InsideASTSExpandableCard(
            title: "Sources",
            subtitle: "Primary references",
            iconName: "link",
            isExpanded: isSectionExpanded(.links),
            onToggle: { toggleSection(.links) },
            assetName: nil,
            fallbackTitle: ""
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(InsideASTSContent.sourceReferences) { reference in
                    InsideASTSSourceLinkRow(title: reference.title, url: reference.url)
                }
            }
        }
    }

    /// Convenience helper keeps section checks readable at call sites.
    private func isSectionExpanded(_ id: SectionID) -> Bool {
        expandedSections.contains(id)
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
