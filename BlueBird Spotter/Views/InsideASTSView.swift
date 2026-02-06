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

            Text("AST SpaceMobile is building a space-based cellular network that talks directly to normal smartphones. This tab gives a high-level look at the company, the BlueBird satellites, and how this app turns TLE data into a live globe experience.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                metricChip(title: "Coverage Vision", value: "Global")
                metricChip(title: "MNO Agreements", value: "50+")
                metricChip(title: "Subscriber Reach", value: "~3B")
            }

            Text("Data snapshot references: public AST SpaceMobile materials (as of February 2026).")
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
                bullet("AST SpaceMobile's mission is to eliminate cellular dead zones by extending broadband directly to standard 4G/5G phones from space.")
                bullet("AST's FAQ states the company has agreements with over 50 mobile network operators, representing nearly 3 billion combined subscribers.")
                bullet("AST lists eight strategic partners: AT&T, Verizon, Vodafone, Rakuten, Google, American Tower, Bell Canada, and stc group.")
                bullet("AST highlights a large IP position for direct-to-device systems, with over 3,400 patent families and more than 3,800 patents and patent-pending claims.")
                bullet("Commercial deployment accelerated with the first BlueBird satellites in 2024 and the first next-generation BlueBird launch in late 2025.")
                bullet("Earlier demonstrations included first-of-kind voice, video, and 5G milestones from space to unmodified smartphones.")
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
                bullet("AST launched its first five commercial BlueBird satellites in September 2024.")
                bullet("Each satellite unfolded a large communications array (~693 sq. ft.) to connect with everyday phones from low Earth orbit.")

                Text("Block 2 / FM-1 Era")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                bullet("The first next-generation BlueBird (BlueBird 6, often called FM-1 in community discussions) launched in December 2025.")
                bullet("AST states this design increases processing bandwidth by more than 10x compared to first-generation BlueBirds.")
                bullet("AST also references significantly larger phased-array scale for next-gen architecture (>2,400 sq. ft.).")
                bullet("The strategic goal is straightforward: higher capacity, stronger service quality, and broader direct-to-device scale through partner MNOs.")
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
                processStep(
                    title: "1) TLE ingestion and refresh",
                    description: "The app fetches AST-related TLEs from CelesTrak, caches them locally, and treats data as stale after about 6 hours. That is a practical refresh window because TLE updates are periodic and not truly real-time telemetry."
                )
                processStep(
                    title: "2) Real-time tracking loop",
                    description: "Once seeded with current TLEs, the tracking engine runs at 1 Hz (once per second). On each tick, it propagates each orbit forward to 'now' and updates latitude, longitude, altitude, and velocity."
                )
                processStep(
                    title: "3) Lat/Lon/Alt and velocity mapping",
                    description: "Orbital state starts in an inertial frame and is converted into Earth-fixed geodetic coordinates for UI display. Velocity is shown as the speed magnitude, which helps users compare orbital motion at a glance."
                )
                processStep(
                    title: "4) Short-horizon prediction",
                    description: "Between TLE refreshes, the app keeps projecting motion from the latest TLE set. This provides smooth near-term estimates for the next minutes to hours until newer element sets arrive."
                )
                processStep(
                    title: "5) Orbital path rendering",
                    description: "The globe samples points around each orbit period and draws path geometry in 3D. Similar orbits are deduplicated so large constellations stay readable and performant."
                )
                processStep(
                    title: "6) Real-time sunlight",
                    description: "Directional sunlight is computed from UTC date/time, Earth's tilt, and Earth rotation (GMST). That keeps day/night placement aligned with real-world solar position as time advances."
                )
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
                bullet("This app aims for realistic, educational approximations of AST satellite behavior using public orbital elements and standard propagation methods.")
                bullet("Real-world orbital prediction is inherently noisy: drag, maneuvers, attitude changes, upload latency, and model assumptions all introduce error.")
                bullet("TLE data itself is an estimation product, so projected positions can drift until refreshed with newer element sets.")
                bullet("Rendering choices (sampling density, smoothing, and visual scaling) are tuned for readability, not mission operations.")

                Text("This is a hobby app for ASTS enthusiasts and interested investors. It is not a flight operations or safety-critical tool, and no guarantee of exact real-time precision is implied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background {
                        secondaryCardBackground(cornerRadius: 10)
                    }

                Text("Nothing in this app is financial advice.")
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
                sourceLink("AST SpaceMobile FAQ", url: "https://ast-science.com/faq/")
                sourceLink("AST Strategic Partners", url: "https://ast-science.com/partners/")
                sourceLink("AST 'The Next-Generation Space-Based Cellular Broadband Network'", url: "https://ast-science.com/the-next-generation-space-based-cellular-broadband-network/")
                sourceLink("AST Company Timeline / Journey", url: "https://ast-science.com/company/our-journey/")
                sourceLink("BlueBird 1-5 profile", url: "https://ast-science.com/bluebird-1-5/")
                sourceLink("Next-Generation BlueBird profile", url: "https://ast-science.com/next-gen-bluebird/")
                sourceLink("BlueBird launch news (Sept 2024)", url: "https://ast-science.com/2024/09/24/ast-spacemobile-bluebird-1-5-satellite-mission-launches-from-florida/")
                sourceLink("BlueBird 6 launch news (Dec 2025)", url: "https://ast-science.com/2025/12/23/ast-spacemobile-successfully-launches-bluebird-6-the-first-next-generation-satellite-in-its-cellular-broadband-network/")
                sourceLink("SEC filings (ASTS investor relations)", url: "https://ast-science.com/investor-relations/financial-information/sec-filings/")
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
