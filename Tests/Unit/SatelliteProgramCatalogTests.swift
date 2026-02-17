//
//  SatelliteProgramCatalogTests.swift
//  BlueBird SpotterTests
//
//  Created by Codex on 2/17/26.
//

import Foundation
import Testing
@testable import BlueBird_Spotter

/// Validates category and naming policy for known AST satellites.
struct SatelliteProgramCatalogTests {
    /// Known Block 1 NORAD ids should classify as Block 1 with smaller estimate profile.
    @Test @MainActor func descriptor_block1Norad_mapsToBlock1() {
        let satellite = Satellite(
            id: 61_047,
            name: "SPACEMOBILE-001",
            tleLine1: "1 61047U 24234A   26048.00000000  .00001000  00000-0  00000-0 0  9991",
            tleLine2: "2 61047  53.0000  20.0000 0001000  90.0000 270.0000 15.20000000000001",
            epoch: nil
        )

        let descriptor = SatelliteProgramCatalog.descriptor(for: satellite)

        #expect(descriptor.category == .blueBirdBlock(1))
        #expect(descriptor.displayName == "SPACEMOBILE-001")
        #expect(descriptor.coverageEstimateModel == .minimumElevationDegrees(35))
    }

    /// BlueWalker 3 should classify independently from BlueBird blocks.
    @Test @MainActor func descriptor_blueWalkerNorad_mapsToBlueWalker() {
        let satellite = Satellite(
            id: 53_807,
            name: "BLUEWALKER 3",
            tleLine1: "1 53807U 22111A   26048.00000000  .00001000  00000-0  00000-0 0  9991",
            tleLine2: "2 53807  53.0000  20.0000 0001000  90.0000 270.0000 15.20000000000001",
            epoch: nil
        )

        let descriptor = SatelliteProgramCatalog.descriptor(for: satellite)

        #expect(descriptor.category == .blueWalker)
        #expect(descriptor.displayName == "BlueWalker 3")
        #expect(descriptor.coverageEstimateModel == .fixedGroundRadiusKm(500))
    }

    /// Block 2+ satellites should present BlueBird naming in the info overlay.
    @Test @MainActor func descriptor_block2Name_mapsToBlueBirdDisplayName() {
        let satellite = Satellite(
            id: 67_232,
            name: "SPACEMOBILE-006",
            tleLine1: "1 67232U 25200A   26048.00000000  .00001000  00000-0  00000-0 0  9991",
            tleLine2: "2 67232  53.0000  20.0000 0001000  90.0000 270.0000 15.20000000000001",
            epoch: nil
        )

        let descriptor = SatelliteProgramCatalog.descriptor(for: satellite)

        #expect(descriptor.category == .blueBirdBlock(2))
        #expect(descriptor.displayName == "BlueBird 6")
        #expect(descriptor.coverageEstimateModel == .minimumElevationDegrees(20))
    }

    /// TLE metadata resolution should classify BlueWalker entries correctly.
    @Test @MainActor func descriptor_forTLEName_blueWalkerLine_mapsToBlueWalkerCategory() {
        let descriptor = SatelliteProgramCatalog.descriptor(
            forTLEName: "BLUEWALKER 3",
            line1: "1 53807U 22111A   26048.00000000  .00001000  00000-0  00000-0 0  9991"
        )

        #expect(descriptor.category == .blueWalker)
    }

    /// Future Block 2+ rows should derive BlueBird naming from SpaceMobile serials.
    @Test @MainActor func descriptor_futureSpaceMobileSerial_usesBlueBirdDisplayName() {
        let satellite = Satellite(
            id: 70_007,
            name: "SPACEMOBILE-007",
            tleLine1: "1 70007U 26001A   26048.00000000  .00001000  00000-0  00000-0 0  9991",
            tleLine2: "2 70007  53.0000  20.0000 0001000  90.0000 270.0000 15.20000000000001",
            epoch: nil
        )

        let descriptor = SatelliteProgramCatalog.descriptor(for: satellite)

        #expect(descriptor.category == .blueBirdBlock(2))
        #expect(descriptor.displayName == "BlueBird 7")
    }
}
