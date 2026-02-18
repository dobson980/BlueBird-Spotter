//
//  SatelliteProgramCatalog.swift
//  BlueBird Spotter
//
//  Created by Codex on 2/17/26.
//

import Foundation

/// High-level category for known AST program satellites.
///
/// This enum intentionally keeps categories broad so UI surfaces can group
/// satellites in a way that is stable, educational, and easy to extend.
enum SatelliteProgramCategory: Hashable, Sendable, Comparable {
    /// BlueBird production satellites grouped by program block.
    case blueBirdBlock(Int)
    /// BlueWalker prototype line.
    case blueWalker
    /// Fallback for entries we cannot confidently classify yet.
    case unknown

    /// Human-friendly title used in section headers and overlays.
    var label: String {
        switch self {
        case .blueBirdBlock(let blockNumber):
            return "Block \(blockNumber)"
        case .blueWalker:
            return "BlueWalker"
        case .unknown:
            return "Unclassified"
        }
    }

    /// Sort order keeps known categories grouped predictably across tabs.
    private var sortPriority: Int {
        switch self {
        case .blueBirdBlock(let blockNumber):
            // Requested reading order: Block 1, BlueWalker, Block 2+.
            if blockNumber <= 1 { return 10 }
            if blockNumber == 2 { return 30 }
            return 30 + blockNumber
        case .blueWalker:
            return 20
        case .unknown:
            return 100
        }
    }

    static func < (lhs: SatelliteProgramCategory, rhs: SatelliteProgramCategory) -> Bool {
        if lhs.sortPriority != rhs.sortPriority {
            return lhs.sortPriority < rhs.sortPriority
        }
        return lhs.label < rhs.label
    }
}

/// Coverage-sizing model used by the educational globe overlay.
enum SatelliteCoverageEstimateModel: Sendable, Equatable {
    /// Uses geometry with a minimum elevation threshold.
    case minimumElevationDegrees(Double)
    /// Uses minimum-elevation geometry with an additional off-nadir scan clamp.
    case minimumElevationWithScanLimit(minimumElevationDegrees: Double, maxOffNadirDegrees: Double)
    /// Uses a fixed effective ground-radius estimate.
    case fixedGroundRadiusKm(Double)
}

/// Computed metadata for one satellite entry.
struct SatelliteProgramDescriptor: Sendable, Equatable {
    /// Category used for UI grouping and education labels.
    let category: SatelliteProgramCategory
    /// Preferred display name shown in high-level UI.
    let displayName: String
    /// Coverage approximation profile for globe overlays.
    let coverageEstimateModel: SatelliteCoverageEstimateModel
}

/// Resolves known AST satellite naming, grouping, and coverage heuristics.
///
/// Why this exists:
/// - Multiple tabs need consistent categorization (Block 1 / BlueWalker / Block 2+).
/// - The globe overlay needs different radius assumptions per generation.
///
/// What this does NOT do:
/// - It does not claim mission-operations precision.
/// - It intentionally favors readable, user-facing estimates.
enum SatelliteProgramCatalog {
    /// Query keys used across tabs to include both SpaceMobile satellites and BW3.
    ///
    /// We intentionally query "BLUEWALKER" (not "BLUEWALKER 3") because
    /// CelesTrak's NAME filter is substring-based and the canonical record is
    /// published as "BLUEWALKER-3" with a hyphen.
    nonisolated static let defaultQueryKeys: [String] = ["SPACEMOBILE", "BLUEWALKER"]

    /// Known NORAD id for BlueWalker 3.
    nonisolated private static let blueWalkerNoradIDs: Set<Int> = [53_807]
    /// Lightweight scan clamp used for BlueBird educational footprint limits.
    nonisolated private static let blueBirdMaxOffNadirDegrees: Double = 58

    /// Known BlueBird serial number by NORAD id.
    ///
    /// Keeping this map centralized makes future updates straightforward as
    /// additional BlueBird satellites are cataloged.
    nonisolated private static let blueBirdSerialByNoradID: [Int: Int] = [
        61_047: 1,
        61_048: 2,
        61_045: 3,
        61_049: 4,
        61_046: 5,
        67_232: 6
    ]

    /// Explicit block assignment by NORAD id for known satellites.
    nonisolated private static let blueBirdBlockByNoradID: [Int: Int] = [
        61_047: 1,
        61_048: 1,
        61_045: 1,
        61_049: 1,
        61_046: 1,
        67_232: 2
    ]

    /// Serial-to-block rules derived from current public naming conventions.
    ///
    /// A wide upper bound keeps behavior stable until a future block mapping
    /// is explicitly introduced.
    nonisolated private static let serialBlockRules: [(range: ClosedRange<Int>, block: Int)] = [
        (1...5, 1),
        (6...9_999, 2)
    ]

    /// Returns normalized metadata for a tracked satellite model.
    nonisolated static func descriptor(for satellite: Satellite) -> SatelliteProgramDescriptor {
        descriptor(noradID: satellite.id, rawName: satellite.name)
    }

    /// Returns normalized metadata for a raw TLE row.
    nonisolated static func descriptor(forTLEName name: String?, line1: String) -> SatelliteProgramDescriptor {
        descriptor(noradID: SatelliteIDParser.parseNoradId(line1: line1), rawName: name ?? "Unknown")
    }

    /// Computes the educational coverage-radius estimate in kilometers.
    nonisolated static func estimatedCoverageGroundRadiusKm(
        for satellite: Satellite,
        altitudeKm: Double
    ) -> Double? {
        let descriptor = descriptor(for: satellite)
        switch descriptor.coverageEstimateModel {
        case .fixedGroundRadiusKm(let radiusKm):
            return radiusKm
        case .minimumElevationDegrees(let minimumElevation):
            return SatelliteCoverageFootprint.groundRadiusKm(
                altitudeKm: altitudeKm,
                minimumElevationDegrees: minimumElevation
            )
        case .minimumElevationWithScanLimit(let minimumElevation, let maxOffNadir):
            return SatelliteCoverageFootprint.groundRadiusKm(
                altitudeKm: altitudeKm,
                minimumElevationDegrees: minimumElevation,
                maximumOffNadirDegrees: maxOffNadir
            )
        }
    }

    /// Formats a compact coverage label for overlay UI.
    nonisolated static func estimatedCoverageLabel(
        for satellite: Satellite,
        altitudeKm: Double
    ) -> String {
        guard let radiusKm = estimatedCoverageGroundRadiusKm(for: satellite, altitudeKm: altitudeKm) else {
            return "Estimate unavailable"
        }
        return "~\(Int(radiusKm.rounded())) km radius (estimate)"
    }

    /// Internal resolver used by both Satellite and TLE entry points.
    nonisolated private static func descriptor(noradID: Int?, rawName: String) -> SatelliteProgramDescriptor {
        let normalizedName = normalizeName(rawName)
        let category = resolveCategory(noradID: noradID, normalizedName: normalizedName)
        let displayName = resolveDisplayName(
            category: category,
            noradID: noradID,
            normalizedName: normalizedName,
            rawName: rawName
        )
        let coverageEstimateModel = resolveCoverageEstimateModel(category: category)
        return SatelliteProgramDescriptor(
            category: category,
            displayName: displayName,
            coverageEstimateModel: coverageEstimateModel
        )
    }

    /// Maps a known satellite into a broad program category.
    nonisolated private static func resolveCategory(
        noradID: Int?,
        normalizedName: String
    ) -> SatelliteProgramCategory {
        if let noradID, blueWalkerNoradIDs.contains(noradID) {
            return .blueWalker
        }
        if normalizedName.contains("BLUEWALKER 3") {
            return .blueWalker
        }

        if let noradID, let knownBlock = blueBirdBlockByNoradID[noradID] {
            return .blueBirdBlock(knownBlock)
        }

        if let serialNumber = extractBlueBirdSerial(from: normalizedName),
           let inferredBlock = blockNumber(forSerialNumber: serialNumber) {
            return .blueBirdBlock(inferredBlock)
        }

        return .unknown
    }

    /// Converts naming conventions into user-facing display labels.
    nonisolated private static func resolveDisplayName(
        category: SatelliteProgramCategory,
        noradID: Int?,
        normalizedName: String,
        rawName: String
    ) -> String {
        let fallbackName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFallback = fallbackName.isEmpty ? "Unknown" : fallbackName

        switch category {
        case .blueWalker:
            return "BlueWalker 3"
        case .blueBirdBlock(let blockNumber):
            // Requested behavior: for Block 2 and beyond, present BlueBird naming.
            guard blockNumber >= 2 else { return safeFallback }
            let serialNumber = noradID.flatMap { blueBirdSerialByNoradID[$0] } ?? extractBlueBirdSerial(from: normalizedName)
            if let serialNumber {
                return "BlueBird \(serialNumber)"
            }
            return "BlueBird"
        case .unknown:
            return safeFallback
        }
    }

    /// Coverage assumptions by category.
    ///
    /// - Block 2+ uses a 20° minimum elevation plus a 58° off-nadir scan clamp.
    /// - Block 1 uses a slightly more conservative 25° minimum elevation with the same clamp.
    /// - BlueWalker 3 uses the public ~300,000 sq mi FoV figure (~500 km effective radius).
    nonisolated private static func resolveCoverageEstimateModel(
        category: SatelliteProgramCategory
    ) -> SatelliteCoverageEstimateModel {
        switch category {
        case .blueWalker:
            return .fixedGroundRadiusKm(500)
        case .blueBirdBlock(let blockNumber):
            if blockNumber == 1 {
                return .minimumElevationWithScanLimit(
                    minimumElevationDegrees: 25,
                    maxOffNadirDegrees: blueBirdMaxOffNadirDegrees
                )
            }
            return .minimumElevationWithScanLimit(
                minimumElevationDegrees: 20,
                maxOffNadirDegrees: blueBirdMaxOffNadirDegrees
            )
        case .unknown:
            return .minimumElevationDegrees(25)
        }
    }

    /// Applies conservative normalization for matching name-based rules.
    nonisolated private static func normalizeName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    /// Extracts the BlueBird serial number from known naming formats.
    nonisolated private static func extractBlueBirdSerial(from normalizedName: String) -> Int? {
        if let serial = extractLeadingDigits(from: normalizedName, afterPrefix: "SPACEMOBILE-") {
            return serial
        }
        if let serial = extractLeadingDigits(from: normalizedName, afterPrefix: "SPACEMOBILE ") {
            return serial
        }
        if let serial = extractLeadingDigits(from: normalizedName, afterPrefix: "BLUEBIRD-") {
            return serial
        }
        if let serial = extractLeadingDigits(from: normalizedName, afterPrefix: "BLUEBIRD ") {
            return serial
        }
        return nil
    }

    /// Converts a known serial into the corresponding program block.
    nonisolated private static func blockNumber(forSerialNumber serialNumber: Int) -> Int? {
        for rule in serialBlockRules where rule.range.contains(serialNumber) {
            return rule.block
        }
        return nil
    }

    /// Reads a numeric prefix immediately after a known textual prefix.
    nonisolated private static func extractLeadingDigits(from text: String, afterPrefix prefix: String) -> Int? {
        guard text.hasPrefix(prefix) else { return nil }
        let suffix = text.dropFirst(prefix.count)
        let digitPrefix = suffix.prefix { $0.isNumber }
        guard !digitPrefix.isEmpty else { return nil }
        return Int(digitPrefix)
    }
}
