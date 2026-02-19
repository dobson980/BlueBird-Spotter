//
//  InsideASTSContent.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 2/6/26.
//

import Foundation

/// Centralized content model for the "Inside ASTS" educational feature.
///
/// Storing long-form copy here keeps the view focused on layout behavior while
/// this model owns the factual text and source-link catalog.
enum InsideASTSContent {
    /// Intro paragraph shown at the top of the screen.
    static let heroIntro = "AST SpaceMobile is building a space-based cellular network designed to connect directly to standard phones. This page summarizes the company, the BlueBird satellites, and how the app models orbit data."

    /// Footnote clarifying when the informational snapshot was compiled.
    static let heroSnapshot = "Sources reviewed: public AST SpaceMobile materials (February 2026)."

    /// Bullet points describing company mission and momentum.
    static let companyBullets: [String] = [
        "The core goal is direct-to-device broadband coverage outside terrestrial cellular range.",
        "AST states it has agreements with 50+ mobile network operators reaching nearly 3 billion subscribers.",
        "Published strategic partners include AT&T, Verizon, Vodafone, Rakuten, Google, American Tower, Bell Canada, and stc group.",
        "AST reports a large direct-to-device IP portfolio, including 3,400+ patent families.",
        "Commercial deployment began with BlueBird launches in 2024 and expanded with the first next-generation BlueBird in late 2025.",
        "Earlier demonstrations included voice, video, and 5G tests from orbit to unmodified phones."
    ]

    /// Bullet points for first-generation BlueBird satellites.
    static let block1Bullets: [String] = [
        "The first five commercial BlueBird satellites launched in September 2024.",
        "Each deployed a communications array of about 693 sq. ft. for direct phone links from low Earth orbit."
    ]

    /// Bullet points for next-generation BlueBird satellites.
    static let block2Bullets: [String] = [
        "The first next-generation BlueBird (BlueBird 6 / FM-1) launched in December 2025.",
        "AST says this generation increases onboard processing bandwidth by more than 10x versus Block 1.",
        "AST also cites phased-array scale above 2,400 sq. ft. in the next-generation design.",
        "The operational target is higher capacity and better quality across partner operator networks."
    ]

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
            description: "The app fetches AST-related TLEs from CelesTrak, caches them locally, and refreshes stale data on roughly a six-hour cadence."
        ),
        ProcessStep(
            title: "2) Real-time tracking loop",
            description: "With current TLEs loaded, a 1 Hz tracking loop propagates each orbit to now and updates latitude, longitude, altitude, and velocity."
        ),
        ProcessStep(
            title: "3) Lat/Lon/Alt and velocity mapping",
            description: "The model converts inertial orbital state into Earth-fixed geodetic coordinates, then displays velocity as scalar speed for quick comparison."
        ),
        ProcessStep(
            title: "4) Short-horizon prediction",
            description: "Between refreshes, motion is projected from the latest TLE set to keep near-term tracking smooth until newer elements arrive."
        ),
        ProcessStep(
            title: "5) Orbital path rendering",
            description: "Orbit paths are sampled in 3D and deduplicated for similar trajectories so dense constellations remain readable and performant."
        ),
        ProcessStep(
            title: "6) Real-time sunlight",
            description: "Directional sunlight is computed from UTC time, Earth tilt, and Earth rotation so day and night align with real-world solar position."
        ),
        ProcessStep(
            title: "7) Coverage estimate",
            description: "The globe can draw an estimated service footprint under each satellite using satellite class, altitude, calibrated elevation masks, and a scan-limit clamp."
        )
    ]

    /// Bullet points that describe model/visualization limits.
    static let accuracyBullets: [String] = [
        "This app is an educational tracker built from public orbital elements and standard propagation methods.",
        "Orbital prediction includes unavoidable uncertainty from drag, maneuvers, attitude changes, data latency, and model assumptions.",
        "TLEs are estimates, so projected positions drift over time until newer element sets are published.",
        "Rendering choices such as sampling density and smoothing prioritize readability over operations-grade fidelity."
    ]

    /// Primary disclaimer paragraph shown in the accuracy section.
    static let disclaimer = "This app is for education and analysis. It is not a flight-operations or safety-critical tool, and exact real-time precision is not guaranteed."

    /// Secondary disclaimer line at the bottom of the section.
    static let financeDisclaimer = "Nothing here is financial advice."

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
        SourceReference(title: "AST Next-Generation Network Overview", url: "https://ast-science.com/the-next-generation-space-based-cellular-broadband-network/"),
        SourceReference(title: "AST Company Timeline", url: "https://ast-science.com/company/our-journey/"),
        SourceReference(title: "BlueBird 1-5 Profile", url: "https://ast-science.com/bluebird-1-5/"),
        SourceReference(title: "Next-Generation BlueBird Profile", url: "https://ast-science.com/next-gen-bluebird/"),
        SourceReference(title: "BlueBird 1-5 Launch (Sep 2024)", url: "https://ast-science.com/2024/09/24/ast-spacemobile-bluebird-1-5-satellite-mission-launches-from-florida/"),
        SourceReference(title: "BlueBird 6 Launch (Dec 2025)", url: "https://ast-science.com/2025/12/23/ast-spacemobile-successfully-launches-bluebird-6-the-first-next-generation-satellite-in-its-cellular-broadband-network/"),
        SourceReference(title: "SEC filings (ASTS investor relations)", url: "https://ast-science.com/investor-relations/financial-information/sec-filings/")
    ]
}
