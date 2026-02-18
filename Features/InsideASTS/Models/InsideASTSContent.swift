//
//  InsideASTSContent.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/6/26.
//

import Foundation

/// Centralized content model for the "Inside ASTS" educational feature.
///
/// Storing long-form copy here keeps the view focused on layout behavior while
/// this model owns the factual text and source-link catalog.
enum InsideASTSContent {
    /// Intro paragraph shown at the top of the screen.
    static let heroIntro = "AST SpaceMobile is building a space-based cellular network that talks directly to normal smartphones. This tab gives a high-level look at the company, the BlueBird satellites, and how this app turns TLE data into a live globe experience."

    /// Footnote clarifying when the informational snapshot was compiled.
    static let heroSnapshot = "Data snapshot references: public AST SpaceMobile materials (as of February 2026)."

    /// Bullet points describing company mission and momentum.
    static let companyBullets: [String] = [
        "AST SpaceMobile's mission is to eliminate cellular dead zones by extending broadband directly to standard 4G/5G phones from space.",
        "AST's FAQ states the company has agreements with over 50 mobile network operators, representing nearly 3 billion combined subscribers.",
        "AST lists eight strategic partners: AT&T, Verizon, Vodafone, Rakuten, Google, American Tower, Bell Canada, and stc group.",
        "AST highlights a large IP position for direct-to-device systems, with over 3,400 patent families and more than 3,800 patents and patent-pending claims.",
        "Commercial deployment accelerated with the first BlueBird satellites in 2024 and the first next-generation BlueBird launch in late 2025.",
        "Earlier demonstrations included first-of-kind voice, video, and 5G milestones from space to unmodified smartphones."
    ]

    /// Bullet points for first-generation BlueBird satellites.
    static let block1Bullets: [String] = [
        "AST launched its first five commercial BlueBird satellites in September 2024.",
        "Each satellite unfolded a large communications array (~693 sq. ft.) to connect with everyday phones from low Earth orbit."
    ]

    /// Bullet points for next-generation BlueBird satellites.
    static let block2Bullets: [String] = [
        "The first next-generation BlueBird (BlueBird 6, often called FM-1 in community discussions) launched in December 2025.",
        "AST states this design increases processing bandwidth by more than 10x compared to first-generation BlueBirds.",
        "AST also references significantly larger phased-array scale for next-gen architecture (>2,400 sq. ft.).",
        "The strategic goal is straightforward: higher capacity, stronger service quality, and broader direct-to-device scale through partner MNOs."
    ]

    /// Short title for the coverage callout inside the app-flow section.
    static let coverageWorkflowTitle = "Coverage Circles (Estimate)"

    /// Brief explanation of what coverage circles mean in the globe tab.
    static let coverageWorkflowNote = "The globe can draw a semi-transparent footprint under each satellite to show an approximate service region. It follows the satellite in real time and uses category-based assumptions (for example, Block 1 and BlueWalker 3 footprints appear smaller than Block 2 BlueBird). This is a rough educational estimate, not operationally precise."

    /// Represents one high-level step in the app's data and rendering pipeline.
    struct ProcessStep: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let description: String
    }

    /// Ordered process steps shown in the "How This App Works" card.
    static let processSteps: [ProcessStep] = [
        ProcessStep(
            title: "1) TLE ingestion and refresh",
            description: "The app fetches AST-related TLEs from CelesTrak, caches them locally, and treats data as stale after about 6 hours. That is a practical refresh window because TLE updates are periodic and not truly real-time telemetry."
        ),
        ProcessStep(
            title: "2) Real-time tracking loop",
            description: "Once seeded with current TLEs, the tracking engine runs at 1 Hz (once per second). On each tick, it propagates each orbit forward to 'now' and updates latitude, longitude, altitude, and velocity."
        ),
        ProcessStep(
            title: "3) Lat/Lon/Alt and velocity mapping",
            description: "Orbital state starts in an inertial frame and is converted into Earth-fixed geodetic coordinates for UI display. Velocity is shown as the speed magnitude, which helps users compare orbital motion at a glance."
        ),
        ProcessStep(
            title: "4) Short-horizon prediction",
            description: "Between TLE refreshes, the app keeps projecting motion from the latest TLE set. This provides smooth near-term estimates for the next minutes to hours until newer element sets arrive."
        ),
        ProcessStep(
            title: "5) Orbital path rendering",
            description: "The globe samples points around each orbit period and draws path geometry in 3D. Similar orbits are deduplicated so large constellations stay readable and performant."
        ),
        ProcessStep(
            title: "6) Real-time sunlight",
            description: "Directional sunlight is computed from UTC date/time, Earth's tilt, and Earth rotation (GMST). That keeps day/night placement aligned with real-world solar position as time advances."
        )
    ]

    /// Bullet points that describe model/visualization limits.
    static let accuracyBullets: [String] = [
        "This app aims for realistic, educational approximations of AST satellite behavior using public orbital elements and standard propagation methods.",
        "Real-world orbital prediction is inherently noisy: drag, maneuvers, attitude changes, upload latency, and model assumptions all introduce error.",
        "TLE data itself is an estimation product, so projected positions can drift until refreshed with newer element sets.",
        "Rendering choices (sampling density, smoothing, and visual scaling) are tuned for readability, not mission operations."
    ]

    /// Primary disclaimer paragraph shown in the accuracy section.
    static let disclaimer = "This is a hobby app for ASTS enthusiasts and interested investors. It is not a flight operations or safety-critical tool, and no guarantee of exact real-time precision is implied."

    /// Secondary disclaimer line at the bottom of the section.
    static let financeDisclaimer = "Nothing in this app is financial advice."

    /// One external source row with title and URL.
    struct SourceReference: Identifiable, Hashable {
        var id: String { title }
        let title: String
        let url: String
    }

    /// Source links used in the "Primary Sources" section.
    static let sourceReferences: [SourceReference] = [
        SourceReference(title: "AST SpaceMobile FAQ", url: "https://ast-science.com/faq/"),
        SourceReference(title: "AST Strategic Partners", url: "https://ast-science.com/partners/"),
        SourceReference(title: "AST 'The Next-Generation Space-Based Cellular Broadband Network'", url: "https://ast-science.com/the-next-generation-space-based-cellular-broadband-network/"),
        SourceReference(title: "AST Company Timeline / Journey", url: "https://ast-science.com/company/our-journey/"),
        SourceReference(title: "BlueBird 1-5 profile", url: "https://ast-science.com/bluebird-1-5/"),
        SourceReference(title: "Next-Generation BlueBird profile", url: "https://ast-science.com/next-gen-bluebird/"),
        SourceReference(title: "BlueBird launch news (Sept 2024)", url: "https://ast-science.com/2024/09/24/ast-spacemobile-bluebird-1-5-satellite-mission-launches-from-florida/"),
        SourceReference(title: "BlueBird 6 launch news (Dec 2025)", url: "https://ast-science.com/2025/12/23/ast-spacemobile-successfully-launches-bluebird-6-the-first-next-generation-satellite-in-its-cellular-broadband-network/"),
        SourceReference(title: "SEC filings (ASTS investor relations)", url: "https://ast-science.com/investor-relations/financial-information/sec-filings/")
    ]
}
